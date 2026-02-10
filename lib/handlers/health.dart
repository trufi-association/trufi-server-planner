import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../state.dart';

Response healthHandler(Request request) {
  return Response.ok(
    jsonEncode({
      'status': 'healthy',
      'service': 'trufi-server-planner',
      'gtfs': {
        'stops': gtfsData.stops.length,
        'routes': gtfsData.routes.length,
        'trips': gtfsData.trips.length,
        'shapes': gtfsData.shapes.length,
      },
    }),
    headers: {'Content-Type': 'application/json'},
  );
}
