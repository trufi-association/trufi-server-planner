class GtfsRoute {
  final String routeId;
  final String routeShortName;
  final String routeLongName;
  final String? routeType;
  final String? routeColor;
  final String? routeTextColor;

  GtfsRoute({
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    this.routeType,
    this.routeColor,
    this.routeTextColor,
  });

  factory GtfsRoute.fromCsv(List<String> headers, List<String> values) {
    // Pad values with empty strings if needed
    final paddedValues = List<String>.from(values);
    while (paddedValues.length < headers.length) {
      paddedValues.add('');
    }

    final map = Map.fromIterables(headers, paddedValues);
    return GtfsRoute(
      routeId: map['route_id'] ?? '',
      routeShortName: map['route_short_name'] ?? '',
      routeLongName: map['route_long_name'] ?? '',
      routeType: map['route_type']?.isNotEmpty == true ? map['route_type'] : null,
      routeColor: map['route_color']?.isNotEmpty == true ? map['route_color'] : null,
      routeTextColor: map['route_text_color']?.isNotEmpty == true ? map['route_text_color'] : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': routeId,
        'shortName': routeShortName,
        'longName': routeLongName,
        'type': routeType,
        'color': routeColor,
        'textColor': routeTextColor,
      };
}
