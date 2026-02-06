import 'package:latlong2/latlong.dart';

class GtfsStop {
  final String stopId;
  final String stopName;
  final double stopLat;
  final double stopLon;
  final String? stopCode;
  final String? stopDesc;

  GtfsStop({
    required this.stopId,
    required this.stopName,
    required this.stopLat,
    required this.stopLon,
    this.stopCode,
    this.stopDesc,
  });

  LatLng get location => LatLng(stopLat, stopLon);

  factory GtfsStop.fromCsv(List<String> headers, List<String> values) {
    // Pad values with empty strings if needed
    final paddedValues = List<String>.from(values);
    while (paddedValues.length < headers.length) {
      paddedValues.add('');
    }

    final map = Map.fromIterables(headers, paddedValues);
    return GtfsStop(
      stopId: map['stop_id'] ?? '',
      stopName: map['stop_name'] ?? '',
      stopLat: double.tryParse(map['stop_lat'] ?? '0') ?? 0,
      stopLon: double.tryParse(map['stop_lon'] ?? '0') ?? 0,
      stopCode: map['stop_code']?.isNotEmpty == true ? map['stop_code'] : null,
      stopDesc: map['stop_desc']?.isNotEmpty == true ? map['stop_desc'] : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': stopId,
        'name': stopName,
        'lat': stopLat,
        'lon': stopLon,
        'code': stopCode,
        'desc': stopDesc,
      };
}
