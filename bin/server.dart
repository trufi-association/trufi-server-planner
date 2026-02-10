import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:trufi_core_planner/trufi_core_planner.dart';

import 'package:trufi_server_planner/state.dart';
import 'package:trufi_server_planner/middleware.dart';
import 'package:trufi_server_planner/handlers/health.dart';
import 'package:trufi_server_planner/handlers/stops.dart';
import 'package:trufi_server_planner/handlers/routes.dart';
import 'package:trufi_server_planner/handlers/plan.dart';
import 'package:trufi_server_planner/handlers/docs.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;

  print('=== Trufi Server Planner ===');
  print('Loading GTFS data...');

  try {
    gtfsData = await GtfsParser.parseFromFile('gtfs_data.zip');
    spatialIndex = GtfsSpatialIndex(gtfsData.stops);
    routeIndex = GtfsRouteIndex(gtfsData);
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

  // API routes
  final apiRouter = Router()
    ..get('/api/health', healthHandler)
    ..get('/api/stops', listStopsHandler)
    ..get('/api/stops/nearby', nearbyStopsHandler)
    ..get('/api/routes', listRoutesHandler)
    ..get('/api/routes/<id>', getRouteHandler)
    ..post('/api/plan', planHandler)
    ..get('/api/docs', swaggerUiHandler)
    ..get('/api/openapi.json', openApiSpecHandler);

  // Static file handler for Flutter web app
  final staticHandler = createStaticHandler(
    'web',
    defaultDocument: 'index.html',
  );

  // Cascade: API first, then static files
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsMiddleware())
      .addHandler(
        Cascade()
            .add(apiRouter.call)
            .add(staticHandler)
            .handler,
      );

  final server = await shelf_io.serve(handler, '0.0.0.0', port);
  print('Server listening on http://${server.address.host}:${server.port}');
  print('Web app available at http://${server.address.host}:${server.port}/');
  print('API docs at http://${server.address.host}:${server.port}/api/docs');
}
