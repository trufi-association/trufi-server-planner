import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shelf/shelf.dart';

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

    final paths = routingService.findRoutes(
      origin: LatLng(fromLat, fromLon),
      destination: LatLng(toLat, toLon),
      maxWalkDistance: 500,
      maxResults: 5,
    );

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
