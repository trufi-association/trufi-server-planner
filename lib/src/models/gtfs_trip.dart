class GtfsTrip {
  final String tripId;
  final String routeId;
  final String serviceId;
  final String? tripHeadsign;
  final String? directionId;
  final String? shapeId;

  GtfsTrip({
    required this.tripId,
    required this.routeId,
    required this.serviceId,
    this.tripHeadsign,
    this.directionId,
    this.shapeId,
  });

  factory GtfsTrip.fromCsv(List<String> headers, List<String> values) {
    // Pad values with empty strings if needed
    final paddedValues = List<String>.from(values);
    while (paddedValues.length < headers.length) {
      paddedValues.add('');
    }

    final map = Map.fromIterables(headers, paddedValues);
    return GtfsTrip(
      tripId: map['trip_id'] ?? '',
      routeId: map['route_id'] ?? '',
      serviceId: map['service_id'] ?? '',
      tripHeadsign: map['trip_headsign']?.isNotEmpty == true ? map['trip_headsign'] : null,
      directionId: map['direction_id']?.isNotEmpty == true ? map['direction_id'] : null,
      shapeId: map['shape_id']?.isNotEmpty == true ? map['shape_id'] : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': tripId,
        'routeId': routeId,
        'serviceId': serviceId,
        'headsign': tripHeadsign,
        'directionId': directionId,
        'shapeId': shapeId,
      };
}
