import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shelf/shelf.dart';

import '../state.dart';

/// Bounds of the search knobs a client may send in the `/plan` body.
///
/// The defaults are the planner's own (`GtfsRoutingService.findRoutes`), so
/// a client that sends nothing gets exactly what it got before the knobs
/// were read. Values above the cap are clamped — the server protects itself
/// and the answer stays useful (same rule as `maxResults` and
/// `maxWalkDistance`); values below the floor or of the wrong type cannot
/// mean anything and are rejected with 400.
///
/// The stop-pool cap is a COST bound, not a coverage bound. `findRoutes`
/// is synchronous on the server's single isolate, so one request's search
/// blocks every other request (including /api/health) for as long as it
/// runs, and the direct phase grows superlinearly with the pool. Measured
/// on the pinned planner compiled AOT like the container (Cochabamba feed
/// of 23 671 stops, 2 000 m walk — the walk cap): a pool of 150 costs
/// 3-6 ms, 600 costs 29-119 ms, 800 costs 61-202 ms, 1 000 costs
/// 99-296 ms (best of three on four pairs; over HTTP on 100 downtown pairs
/// the p95 is 101, 184 and 276 ms for 600, 800 and 1 000, and at the 800 m
/// walk the app sends 99, 123 and 123 ms). 800 is what the densest city
/// that configures the knob needs (Cochabamba, trufi-app#71: no stop there
/// has more than 778 neighbours within its 800 m walking radius, so 800 is
/// "every stop in range" and 1 000 would cost the same; Sana'a sends 600,
/// trufi-sanaa#28, no stop there has more than 520 within 1 500 m). At the
/// 2 000 m walk cap Cochabamba's densest stops have ~3 000 neighbours, so
/// there the cap does truncate the radius — by design, the price of
/// keeping a request around 0.1-0.2 s. Raising it is one constant.
///
/// The transfer cap: the multi-transfer search finds nothing new above 4-5
/// changes (Sana'a: 96.3 % of random pairs plannable with 4, 99.5 % with
/// 5) and stops on its own once no new line is reached. Sana'a ships
/// `maxTransfers: 4`, Bogotá `2`; both fit.
const maxStopCandidatesDefault = 150;
const maxStopCandidatesCap = 800;
const maxTransfersDefault = 1;
const maxTransfersCap = 5;

/// A `/plan` body field the handler cannot honour: answered with 400 and
/// [message], never with the generic 500 of the outer catch.
class BadPlanRequest implements Exception {
  final String message;
  const BadPlanRequest(this.message);

  @override
  String toString() => message;
}

/// Reads an optional numeric field: absent or `null` → [fallback]; not a
/// finite JSON number (string, boolean, `1e400`) → [BadPlanRequest]. The
/// caller converts and clamps, so the #4 rule for `maxResults` and
/// `maxWalkDistance` — out of range means the nearest bound, never a
/// rejection — stays as it was.
num readNumField(
  Map<String, dynamic> json,
  String key, {
  required num fallback,
}) {
  final raw = json[key];
  if (raw == null) return fallback;
  if (raw is! num || !raw.isFinite) {
    throw BadPlanRequest('$key must be a number');
  }
  return raw;
}

/// Reads an optional integer field: absent or `null` → [fallback]; not an
/// integer (string, boolean, fraction) or below [min] → [BadPlanRequest];
/// above [max] → [max]. An integral double (`150.0`) counts as an integer:
/// JSON has one number type and dart2js clients may well produce it.
int readIntField(
  Map<String, dynamic> json,
  String key, {
  required int fallback,
  required int min,
  required int max,
}) {
  final raw = json[key];
  if (raw == null) return fallback;
  // `% 1`, not `truncate()`: truncate() saturates at 2^63-1 on the VM, so
  // 1e19 would read as "not an integer" while 9223372036854775808 (the
  // same value, decoded as a double) would pass. With `% 1` both are
  // integers and clamp to the cap below.
  if (raw is! num || !raw.isFinite || raw % 1 != 0) {
    throw BadPlanRequest('$key must be an integer');
  }
  final value = raw.toInt();
  if (value < min) throw BadPlanRequest('$key must be >= $min');
  return value > max ? max : value;
}

/// Reads an optional boolean field: absent or `null` → [fallback]; anything
/// that is not a JSON boolean → [BadPlanRequest] (no `"false"`, no `0`).
bool readBoolField(
  Map<String, dynamic> json,
  String key, {
  required bool fallback,
}) {
  final raw = json[key];
  if (raw == null) return fallback;
  if (raw is! bool) throw BadPlanRequest('$key must be a boolean');
  return raw;
}

Future<Response> planHandler(Request request) async {
  try {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final fromLat = (json['from']?['lat'] as num?)?.toDouble();
    final fromLon = (json['from']?['lon'] as num?)?.toDouble();
    final toLat = (json['to']?['lat'] as num?)?.toDouble();
    final toLon = (json['to']?['lon'] as num?)?.toDouble();

    if (fromLat == null || fromLon == null || toLat == null || toLon == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing from/to coordinates'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Fields are validated in the order they appear in the OpenAPI spec,
    // after the coordinates; the first offending one is the one reported.
    //
    // Honor the client's requested result count and walk radius, bounded
    // on both sides to keep responses small and searches local (#4: a
    // value below the floor is raised to it, not rejected). Older clients
    // that don't send them get the defaults; a non-numeric value is a 400
    // like the other knobs, not a 500 from a failed cast.
    final maxResults = readNumField(
      json,
      'maxResults',
      fallback: 20,
    ).toInt().clamp(1, 20);
    final maxWalkDistance = readNumField(
      json,
      'maxWalkDistance',
      fallback: 800.0,
    ).toDouble().clamp(100.0, 2000.0);

    // The pool of boarding/alighting stops and the transfer limit, as sent
    // by trufi-core's RemotePlannerClient (`TrufiPlannerConfig.remote`).
    // Both were silently ignored before (#9): a city that raised the pool
    // to reach a far direct line (trufi-sanaa#21) or allowed more changes
    // on a fragmented feed got the planner defaults on the web.
    final maxStopCandidates = readIntField(
      json,
      'maxStopCandidates',
      fallback: maxStopCandidatesDefault,
      min: 1,
      max: maxStopCandidatesCap,
    );
    final maxTransfers = readIntField(
      json,
      'maxTransfers',
      fallback: maxTransfersDefault,
      min: 0,
      max: maxTransfersCap,
    );
    // Validated so a wrong type fails loudly today, but not forwarded: the
    // planner pinned in pubspec.yaml (trufi_core_planner v5.27.0) has no
    // such parameter — its rule is hardwired to "a direct line hides the
    // one-transfer options". The knob lands with trufi-core#1043; once the
    // pin reaches a release that has it, pass the requested value to
    // `findRoutes`, report it instead of the constant, and the ignored
    // list below empties itself.
    final requestedDirectsHideTransfers = readBoolField(
      json,
      'directsHideTransfers',
      fallback: true,
    );
    const directsHideTransfers = true;
    // Fields the client sent that the pinned planner cannot honour, named
    // explicitly: a client that sent `false` and reads `true` should not
    // have to infer the gap from the itineraries.
    final ignoredParameters = [
      if (requestedDirectsHideTransfers != directsHideTransfers)
        'directsHideTransfers',
    ];

    final paths = routingService.findRoutes(
      origin: LatLng(fromLat, fromLon),
      destination: LatLng(toLat, toLon),
      maxWalkDistance: maxWalkDistance,
      maxResults: maxResults,
      maxDirects: maxResults,
      maxTransferPaths: maxResults,
      maxStopCandidates: maxStopCandidates,
      maxTransfers: maxTransfers,
    );

    // What the search actually ran with, after defaults and caps: lets a
    // client (or a curl) tell a clamped or ignored knob from an honoured
    // one without guessing from the itineraries.
    final effectiveParameters = {
      'maxResults': maxResults,
      'maxWalkDistance': maxWalkDistance,
      'maxStopCandidates': maxStopCandidates,
      'maxTransfers': maxTransfers,
      'directsHideTransfers': directsHideTransfers,
    };

    if (paths.isEmpty) {
      return Response.ok(
        jsonEncode({
          'success': false,
          'error': 'No routes found',
          'paths': null,
          'effectiveParameters': effectiveParameters,
          if (ignoredParameters.isNotEmpty)
            'ignoredParameters': ignoredParameters,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({
        'success': true,
        'paths': paths.map((p) => p.toJson()).toList(),
        'count': paths.length,
        'effectiveParameters': effectiveParameters,
        if (ignoredParameters.isNotEmpty)
          'ignoredParameters': ignoredParameters,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } on BadPlanRequest catch (e) {
    return Response.badRequest(
      body: jsonEncode({'error': e.message}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, st) {
    print('Error in /plan: $e');
    print(st);
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
