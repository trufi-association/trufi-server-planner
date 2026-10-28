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
/// Caps come from the core's own measurements (trufi-core#1043,
/// `TrufiPlannerConfig` docs): no stop of the densest feeds has more than
/// ~520 neighbours within 1 500 m, and the multi-transfer search finds
/// nothing new above 4-5 changes (Sana'a: 96.3 % of random pairs plannable
/// with 4, 99.5 % with 5) and stops on its own once no new line is reached.
/// Sana'a ships `maxTransfers: 4`, Bogotá `2`; both fit.
const maxStopCandidatesDefault = 150;
const maxStopCandidatesCap = 1000;
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
  if (raw is! num || !raw.isFinite || raw != raw.truncate()) {
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

    // Honor the client's requested result count and walk radius, bounded
    // to keep responses small and searches local. Older clients that
    // don't send them get the defaults.
    final maxResults = ((json['maxResults'] as num?)?.toInt() ?? 20).clamp(
      1,
      20,
    );
    final maxWalkDistance =
        ((json['maxWalkDistance'] as num?)?.toDouble() ?? 800.0).clamp(
      100.0,
      2000.0,
    );

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
    // pin reaches a release that has it, pass the parsed value to
    // `findRoutes` and report it below instead of the constant.
    readBoolField(json, 'directsHideTransfers', fallback: true);
    const directsHideTransfers = true;

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
