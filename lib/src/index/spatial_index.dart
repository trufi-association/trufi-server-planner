import 'package:latlong2/latlong.dart';
import '../models/gtfs_stop.dart';

class NearbyStop {
  final GtfsStop stop;
  final double distance;

  NearbyStop(this.stop, this.distance);

  Map<String, dynamic> toJson() => {
        'stop': stop.toJson(),
        'distance': distance,
      };
}

class SpatialIndex {
  final Map<String, GtfsStop> stops;
  final Distance _distanceCalculator = const Distance();

  SpatialIndex(this.stops);

  List<NearbyStop> findNearestStops(
    LatLng location, {
    int maxResults = 10,
    double maxDistance = 500.0, // meters
  }) {
    final nearby = <NearbyStop>[];

    for (final stop in stops.values) {
      final distance = _distanceCalculator.as(
        LengthUnit.Meter,
        location,
        stop.location,
      );

      if (distance <= maxDistance) {
        nearby.add(NearbyStop(stop, distance));
      }
    }

    // Sort by distance
    nearby.sort((a, b) => a.distance.compareTo(b.distance));

    // Return top N results
    return nearby.take(maxResults).toList();
  }
}
