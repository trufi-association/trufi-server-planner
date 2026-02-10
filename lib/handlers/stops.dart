import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shelf/shelf.dart';

import '../state.dart';

Response listStopsHandler(Request request) {
  final limit =
      int.tryParse(request.url.queryParameters['limit'] ?? '100') ?? 100;

  final stops =
      gtfsData.stops.values.take(limit).map((s) => s.toJson()).toList();

  return Response.ok(
    jsonEncode({
      'stops': stops,
      'total': gtfsData.stops.length,
    }),
    headers: {'Content-Type': 'application/json'},
  );
}

Future<Response> nearbyStopsHandler(Request request) async {
  try {
    final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final lon = double.tryParse(request.url.queryParameters['lon'] ?? '');
    final maxDistance = double.tryParse(
            request.url.queryParameters['maxDistance'] ?? '500') ??
        500;
    final maxResults =
        int.tryParse(request.url.queryParameters['maxResults'] ?? '10') ?? 10;

    if (lat == null || lon == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing lat/lon parameters'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final location = LatLng(lat, lon);
    final nearbyStops = spatialIndex.findNearestStops(
      location,
      maxResults: maxResults,
      maxDistance: maxDistance,
    );

    return Response.ok(
      jsonEncode({
        'stops': nearbyStops
            .map((ns) => {
                  ...ns.stop.toJson(),
                  'distance': ns.distance,
                })
            .toList(),
        'count': nearbyStops.length,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
