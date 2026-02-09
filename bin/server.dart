import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:latlong2/latlong.dart';
import 'package:trufi_core_planner/trufi_core_planner.dart';

late GtfsData gtfsData;
late GtfsSpatialIndex spatialIndex;
late GtfsRoutingService routingService;
late GtfsRouteIndex routeIndex;

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;

  print('=== Trufi Server Planner ===');
  print('Loading GTFS data...');

  try {
    // Load GTFS data
    gtfsData = await GtfsParser.parseFromFile('gtfs_data.zip');

    // Build indices
    spatialIndex = GtfsSpatialIndex(gtfsData.stops);
    routeIndex = GtfsRouteIndex(gtfsData);

    // Create routing service
    routingService = GtfsRoutingService(
      data: gtfsData,
      spatialIndex: spatialIndex,
      routeIndex: routeIndex,
    );

    print('✓ GTFS data loaded successfully');
    print('  - ${gtfsData.stops.length} stops');
    print('  - ${gtfsData.routes.length} routes');
    print('  - ${gtfsData.trips.length} trips');
    print('  - ${gtfsData.stopTimes.length} stop times');
  } catch (e, st) {
    print('✗ Failed to load GTFS data: $e');
    print(st);
    exit(1);
  }

  // Create API router
  final apiRouter = Router()
    ..get('/health', _healthHandler)
    ..get('/stops', _listStopsHandler)
    ..get('/stops/nearby', _nearbyStopsHandler)
    ..get('/routes', _listRoutesHandler)
    ..post('/plan', _planHandler);

  // Create static file handler for web app
  final staticHandler = createStaticHandler(
    'web',
    defaultDocument: 'index.html',
  );

  // Create cascade: try API routes first, then static files
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(
        Cascade()
            .add(apiRouter.call)
            .add(staticHandler)
            .handler,
      );

  // Start server
  final server = await shelf_io.serve(handler, '0.0.0.0', port);
  print('Server listening on http://${server.address.host}:${server.port}');
  print('Web app available at http://${server.address.host}:${server.port}/');
}

// Middleware for CORS
Middleware _corsMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }

      final response = await handler(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

final _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

// Health check
Response _healthHandler(Request request) {
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

// List all stops
Response _listStopsHandler(Request request) {
  final limit = int.tryParse(request.url.queryParameters['limit'] ?? '100') ?? 100;

  final stops = gtfsData.stops.values.take(limit).map((s) => s.toJson()).toList();

  return Response.ok(
    jsonEncode({
      'stops': stops,
      'total': gtfsData.stops.length,
    }),
    headers: {'Content-Type': 'application/json'},
  );
}

// Find nearby stops
Future<Response> _nearbyStopsHandler(Request request) async {
  try {
    final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
    final lon = double.tryParse(request.url.queryParameters['lon'] ?? '');
    final maxDistance = double.tryParse(request.url.queryParameters['maxDistance'] ?? '500') ?? 500;
    final maxResults = int.tryParse(request.url.queryParameters['maxResults'] ?? '10') ?? 10;

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
        'stops': nearbyStops.map((ns) => {
          ...ns.stop.toJson(),
          'distance': ns.distance,
        }).toList(),
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

// List all routes
Response _listRoutesHandler(Request request) {
  final routes = gtfsData.routes.values.map((r) => r.toJson()).toList();

  return Response.ok(
    jsonEncode({
      'routes': routes,
      'total': routes.length,
    }),
    headers: {'Content-Type': 'application/json'},
  );
}

// Plan a route
Future<Response> _planHandler(Request request) async {
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

    // Find routes using the routing service
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
