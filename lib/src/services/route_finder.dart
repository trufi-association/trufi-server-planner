import 'package:latlong2/latlong.dart';
import '../models/gtfs_stop.dart';
import '../models/gtfs_route.dart';
import '../models/gtfs_trip.dart';
import '../models/gtfs_stop_time.dart';
import '../parser/gtfs_parser.dart';
import '../index/spatial_index.dart';

/// A segment of a routing path (one transit leg).
class RouteSegment {
  final GtfsRoute route;
  final GtfsStop fromStop;
  final GtfsStop toStop;
  final List<String> stopIds;
  final int stopCount;

  RouteSegment({
    required this.route,
    required this.fromStop,
    required this.toStop,
    required this.stopIds,
  }) : stopCount = stopIds.length;

  Map<String, dynamic> toJson() => {
        'route': route.toJson(),
        'from': fromStop.toJson(),
        'to': toStop.toJson(),
        'stopCount': stopCount,
      };
}

/// A complete routing path from origin to destination.
class RoutePath {
  final double originWalkDistance;
  final GtfsStop originStop;
  final List<RouteSegment> segments;
  final GtfsStop destinationStop;
  final double destinationWalkDistance;

  RoutePath({
    required this.originWalkDistance,
    required this.originStop,
    required this.segments,
    required this.destinationStop,
    required this.destinationWalkDistance,
  });

  /// Total walk distance in meters.
  double get totalWalkDistance => originWalkDistance + destinationWalkDistance;

  /// Number of transfers.
  int get transfers => segments.isEmpty ? 0 : segments.length - 1;

  /// Total number of stops visited.
  int get totalStops => segments.fold(0, (sum, s) => sum + s.stopCount);

  /// Score for ranking (lower is better).
  double get score {
    return transfers * 1000 + totalWalkDistance * 2 + totalStops * 10;
  }

  Map<String, dynamic> toJson() => {
        'originWalk': originWalkDistance,
        'originStop': originStop.toJson(),
        'segments': segments.map((s) => s.toJson()).toList(),
        'destinationStop': destinationStop.toJson(),
        'destinationWalk': destinationWalkDistance,
        'totalWalk': totalWalkDistance,
        'transfers': transfers,
        'totalStops': totalStops,
        'score': score,
      };
}

/// Service for finding transit routes.
class RouteFinder {
  final GtfsData data;
  final SpatialIndex spatialIndex;

  // Cache for route-to-stops mapping
  late final Map<String, Set<String>> _routeStops;
  late final Map<String, List<String>> _routeStopSequences;

  RouteFinder({
    required this.data,
    required this.spatialIndex,
  }) {
    _buildIndices();
  }

  void _buildIndices() {
    print('RouteFinder: Building route indices...');
    final sw = Stopwatch()..start();

    // Build route-to-stops mapping
    _routeStops = {};
    _routeStopSequences = {};

    // Group stop times by trip
    final tripStopTimes = <String, List<GtfsStopTime>>{};
    for (final st in data.stopTimes) {
      tripStopTimes.putIfAbsent(st.tripId, () => []).add(st);
    }

    // For each trip, get its route and stops
    for (final entry in tripStopTimes.entries) {
      final tripId = entry.key;
      final stopTimes = entry.value
        ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));

      final trip = data.trips[tripId];
      if (trip == null) continue;

      final routeId = trip.routeId;
      final stopIds = stopTimes.map((st) => st.stopId).toList();

      _routeStops.putIfAbsent(routeId, () => {}).addAll(stopIds);

      // Use the first trip sequence as canonical
      if (!_routeStopSequences.containsKey(routeId)) {
        _routeStopSequences[routeId] = stopIds;
      }
    }

    sw.stop();
    print('RouteFinder: Built indices for ${_routeStops.length} routes in ${sw.elapsedMilliseconds}ms');
  }

  /// Find routes from origin to destination.
  List<RoutePath> findRoutes({
    required LatLng origin,
    required LatLng destination,
    double maxWalkDistance = 500,
    int maxResults = 5,
  }) {
    print('RouteFinder: Finding routes...');
    final sw = Stopwatch()..start();

    // Find nearby stops
    final originStops = spatialIndex.findNearestStops(
      origin,
      maxResults: 15,
      maxDistance: maxWalkDistance,
    );

    final destStops = spatialIndex.findNearestStops(
      destination,
      maxResults: 15,
      maxDistance: maxWalkDistance,
    );

    if (originStops.isEmpty || destStops.isEmpty) {
      print('RouteFinder: No nearby stops found');
      return [];
    }

    print('RouteFinder: ${originStops.length} origin stops, ${destStops.length} dest stops');

    final paths = <RoutePath>[];
    final destStopIds = destStops.map((s) => s.stop.stopId).toSet();
    final destStopDistances = {
      for (final s in destStops) s.stop.stopId: s.distance
    };

    // Find direct routes
    for (final originStop in originStops) {
      final routesAtOrigin = _getRoutesAtStop(originStop.stop.stopId);

      for (final routeId in routesAtOrigin) {
        final route = data.routes[routeId];
        if (route == null) continue;

        final path = _findDirectPath(
          originStop: originStop,
          route: route,
          destStopIds: destStopIds,
          destStopDistances: destStopDistances,
        );

        if (path != null) {
          paths.add(path);
        }
      }
    }

    // Sort by score and limit
    paths.sort((a, b) => a.score.compareTo(b.score));

    sw.stop();
    print('RouteFinder: Found ${paths.length} routes in ${sw.elapsedMilliseconds}ms');

    return paths.take(maxResults).toList();
  }

  Set<String> _getRoutesAtStop(String stopId) {
    final routes = <String>{};
    for (final entry in _routeStops.entries) {
      if (entry.value.contains(stopId)) {
        routes.add(entry.key);
      }
    }
    return routes;
  }

  RoutePath? _findDirectPath({
    required NearbyStop originStop,
    required GtfsRoute route,
    required Set<String> destStopIds,
    required Map<String, double> destStopDistances,
  }) {
    final stopSequence = _routeStopSequences[route.routeId];
    if (stopSequence == null) return null;

    // Find origin index
    final originIndex = stopSequence.indexOf(originStop.stop.stopId);
    if (originIndex == -1) return null;

    RoutePath? bestPath;
    double bestScore = double.infinity;

    // Check stops after origin
    for (var i = originIndex + 1; i < stopSequence.length; i++) {
      final stopId = stopSequence[i];
      if (!destStopIds.contains(stopId)) continue;

      final destStop = data.stops[stopId];
      if (destStop == null) continue;

      final stopIds = stopSequence.sublist(originIndex, i + 1);

      final path = RoutePath(
        originWalkDistance: originStop.distance,
        originStop: originStop.stop,
        segments: [
          RouteSegment(
            route: route,
            fromStop: originStop.stop,
            toStop: destStop,
            stopIds: stopIds,
          ),
        ],
        destinationStop: destStop,
        destinationWalkDistance: destStopDistances[stopId] ?? 0,
      );

      if (path.score < bestScore) {
        bestScore = path.score;
        bestPath = path;
      }
    }

    return bestPath;
  }
}
