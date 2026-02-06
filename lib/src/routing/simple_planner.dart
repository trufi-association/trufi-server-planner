import 'package:latlong2/latlong.dart';
import '../models/gtfs_stop.dart';
import '../models/gtfs_route.dart';
import '../models/gtfs_trip.dart';
import '../models/gtfs_stop_time.dart';
import '../parser/gtfs_parser.dart';
import '../index/spatial_index.dart';

class PlanRequest {
  final LatLng from;
  final LatLng to;
  final DateTime? time;

  PlanRequest({
    required this.from,
    required this.to,
    this.time,
  });
}

class PlanResponse {
  final bool success;
  final String? error;
  final List<Itinerary>? itineraries;

  PlanResponse.success(this.itineraries)
      : success = true,
        error = null;

  PlanResponse.error(this.error)
      : success = false,
        itineraries = null;

  Map<String, dynamic> toJson() => {
        'success': success,
        'error': error,
        'itineraries': itineraries?.map((i) => i.toJson()).toList(),
      };
}

class Itinerary {
  final List<Leg> legs;
  final int durationSeconds;

  Itinerary({
    required this.legs,
    required this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'legs': legs.map((l) => l.toJson()).toList(),
        'duration': durationSeconds,
      };
}

class Leg {
  final String mode; // 'TRANSIT' or 'WALK'
  final GtfsStop? fromStop;
  final GtfsStop? toStop;
  final GtfsRoute? route;
  final String? tripId;
  final int durationSeconds;

  Leg({
    required this.mode,
    this.fromStop,
    this.toStop,
    this.route,
    this.tripId,
    required this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'from': fromStop?.toJson(),
        'to': toStop?.toJson(),
        'route': route?.toJson(),
        'tripId': tripId,
        'duration': durationSeconds,
      };
}

class SimplePlanner {
  final GtfsData data;
  final SpatialIndex spatialIndex;

  SimplePlanner({
    required this.data,
    required this.spatialIndex,
  });

  Future<PlanResponse> plan(PlanRequest request) async {
    try {
      // Find nearest stops to origin and destination
      final fromStops = spatialIndex.findNearestStops(
        request.from,
        maxResults: 5,
        maxDistance: 500,
      );

      final toStops = spatialIndex.findNearestStops(
        request.to,
        maxResults: 5,
        maxDistance: 500,
      );

      if (fromStops.isEmpty || toStops.isEmpty) {
        return PlanResponse.error('No stops found near origin or destination');
      }

      // Find direct routes between stops
      final itineraries = <Itinerary>[];

      for (final fromNearby in fromStops) {
        for (final toNearby in toStops) {
          final routes = _findDirectRoutes(
            fromNearby.stop.stopId,
            toNearby.stop.stopId,
          );

          for (final route in routes) {
            // Calculate walking time to/from stops (assume 5 km/h = 1.4 m/s)
            final walkToStop = (fromNearby.distance / 1.4).round();
            final walkFromStop = (toNearby.distance / 1.4).round();

            // Estimate transit time (will be improved with real schedule data)
            final transitTime = 600; // 10 minutes placeholder

            final legs = [
              Leg(
                mode: 'WALK',
                toStop: fromNearby.stop,
                durationSeconds: walkToStop,
              ),
              Leg(
                mode: 'TRANSIT',
                fromStop: fromNearby.stop,
                toStop: toNearby.stop,
                route: route,
                durationSeconds: transitTime,
              ),
              Leg(
                mode: 'WALK',
                fromStop: toNearby.stop,
                durationSeconds: walkFromStop,
              ),
            ];

            itineraries.add(Itinerary(
              legs: legs,
              durationSeconds: walkToStop + transitTime + walkFromStop,
            ));
          }
        }
      }

      if (itineraries.isEmpty) {
        return PlanResponse.error('No routes found');
      }

      // Sort by duration
      itineraries.sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));

      return PlanResponse.success(itineraries.take(3).toList());
    } catch (e, st) {
      print('Error planning route: $e');
      print(st);
      return PlanResponse.error('Internal error: $e');
    }
  }

  List<GtfsRoute> _findDirectRoutes(String fromStopId, String toStopId) {
    // Find all trips that visit both stops in order
    final routeIds = <String>{};

    // Group stop times by trip
    final tripStopTimes = <String, List<GtfsStopTime>>{};
    for (final st in data.stopTimes) {
      tripStopTimes.putIfAbsent(st.tripId, () => []).add(st);
    }

    // Check each trip
    for (final entry in tripStopTimes.entries) {
      final stopTimes = entry.value
        ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));

      var foundFrom = false;
      var foundTo = false;

      for (final st in stopTimes) {
        if (st.stopId == fromStopId) {
          foundFrom = true;
        } else if (st.stopId == toStopId && foundFrom) {
          foundTo = true;
          break;
        }
      }

      if (foundFrom && foundTo) {
        final trip = data.trips[entry.key];
        if (trip != null) {
          routeIds.add(trip.routeId);
        }
      }
    }

    return routeIds
        .map((id) => data.routes[id])
        .whereType<GtfsRoute>()
        .toList();
  }
}
