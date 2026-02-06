class GtfsStopTime {
  final String tripId;
  final String stopId;
  final String arrivalTime;
  final String departureTime;
  final int stopSequence;

  GtfsStopTime({
    required this.tripId,
    required this.stopId,
    required this.arrivalTime,
    required this.departureTime,
    required this.stopSequence,
  });

  factory GtfsStopTime.fromCsv(List<String> headers, List<String> values) {
    final map = Map.fromIterables(headers, values);
    return GtfsStopTime(
      tripId: map['trip_id'] ?? '',
      stopId: map['stop_id'] ?? '',
      arrivalTime: map['arrival_time'] ?? '',
      departureTime: map['departure_time'] ?? '',
      stopSequence: int.tryParse(map['stop_sequence'] ?? '0') ?? 0,
    );
  }

  /// Convert HH:MM:SS to seconds since midnight
  int get arrivalSeconds => _timeToSeconds(arrivalTime);
  int get departureSeconds => _timeToSeconds(departureTime);

  static int _timeToSeconds(String time) {
    final parts = time.split(':');
    if (parts.length != 3) return 0;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final seconds = int.tryParse(parts[2]) ?? 0;
    return hours * 3600 + minutes * 60 + seconds;
  }

  Map<String, dynamic> toJson() => {
        'tripId': tripId,
        'stopId': stopId,
        'arrivalTime': arrivalTime,
        'departureTime': departureTime,
        'stopSequence': stopSequence,
      };
}
