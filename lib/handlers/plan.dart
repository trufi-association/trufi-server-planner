import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:shelf/shelf.dart';
import 'package:trufi_core_planner/trufi_core_planner.dart';

import '../state.dart';

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

    final origin = LatLng(fromLat, fromLon);
    final destination = LatLng(toLat, toLon);

    var paths = routingService.findRoutes(
      origin: origin,
      destination: destination,
      maxWalkDistance: 500,
      maxResults: 10,
    );

    // 1. Filter out redundant same-line transfers (e.g., Line 209 → Line 209)
    final filtered = paths.where((p) => !_hasRedundantSameLineTransfer(p)).toList();
    paths = filtered.isNotEmpty ? filtered : paths;

    // 2. Re-sort with improved scoring
    paths.sort((a, b) => _calculateWeight(a).compareTo(_calculateWeight(b)));

    // 3. Add walk-only option for short distances (< 2.5 km straight line)
    final straightLineMeters = const Distance().as(
      LengthUnit.Meter,
      origin,
      destination,
    );
    if (straightLineMeters <= 2500) {
      paths.add(_buildWalkPath(origin, destination, straightLineMeters));
    }

    // Take top 5 results
    if (paths.length > 5) {
      paths = paths.sublist(0, 5);
    }

    if (paths.isEmpty) {
      return Response.ok(
        jsonEncode({
          'success': false,
          'error': 'No routes found',
          'paths': null,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({
        'success': true,
        'paths': paths.map((p) => p.toJson()).toList(),
        'count': paths.length,
      }),
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

/// Detects itineraries where the same transit line appears consecutively
/// (e.g., Line 209 → Line 209), which indicates an inefficient routing artifact.
bool _hasRedundantSameLineTransfer(RoutingPath path) {
  if (path.segments.length < 2) return false;
  for (int i = 0; i < path.segments.length - 1; i++) {
    final current = path.segments[i].route.shortName;
    final next = path.segments[i + 1].route.shortName;
    if (current.isNotEmpty && current == next) {
      return true;
    }
  }
  return false;
}

/// Improved sorting weight (lower = better).
/// Priorities: fewer transfers > shorter duration estimate > less walking.
double _calculateWeight(RoutingPath path) {
  final transfers = path.transfers;
  final walkKm = path.totalWalkDistance / 1000;
  final totalStops = path.totalStops;
  // Estimate duration: ~2 min per stop + ~12 min/km walking
  final estimatedMinutes = (totalStops * 2) + (walkKm * 12);
  return (transfers * 15) + (estimatedMinutes * 1.0) + (walkKm * 3);
}

/// Builds a synthetic walk-only path between origin and destination.
RoutingPath _buildWalkPath(LatLng origin, LatLng destination, double distanceMeters) {
  // Walking speed ~4.5 km/h → ~75 m/min
  final walkMinutes = distanceMeters / 75;
  // Walk-only paths get a favorable score for short distances
  final score = walkMinutes <= 20 ? walkMinutes * 0.5 : walkMinutes * 2;

  final originStop = GtfsStop(
    id: 'walk_origin',
    name: 'Origin',
    lat: origin.latitude,
    lon: origin.longitude,
  );
  final destinationStop = GtfsStop(
    id: 'walk_destination',
    name: 'Destination',
    lat: destination.latitude,
    lon: destination.longitude,
  );

  return RoutingPath(
    originWalkDistance: distanceMeters,
    originStop: originStop,
    segments: [],
    destinationStop: destinationStop,
    destinationWalkDistance: 0,
    score: score,
  );
}
