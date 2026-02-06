import 'dart:io';
import 'package:archive/archive.dart';
import '../models/gtfs_stop.dart';
import '../models/gtfs_route.dart';
import '../models/gtfs_trip.dart';
import '../models/gtfs_stop_time.dart';

class GtfsData {
  final Map<String, GtfsStop> stops;
  final Map<String, GtfsRoute> routes;
  final Map<String, GtfsTrip> trips;
  final List<GtfsStopTime> stopTimes;

  GtfsData({
    required this.stops,
    required this.routes,
    required this.trips,
    required this.stopTimes,
  });
}

class GtfsParser {
  static Future<GtfsData> parseFromFile(String zipPath) async {
    print('GtfsParser: Loading from $zipPath');
    final bytes = await File(zipPath).readAsBytes();
    return parseFromBytes(bytes);
  }

  static GtfsData parseFromBytes(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    print('GtfsParser: Parsing GTFS files...');
    final stops = _parseStops(archive);
    final routes = _parseRoutes(archive);
    final trips = _parseTrips(archive);
    final stopTimes = _parseStopTimes(archive);

    print('GtfsParser: Parsed ${stops.length} stops, ${routes.length} routes, '
        '${trips.length} trips, ${stopTimes.length} stop times');

    return GtfsData(
      stops: stops,
      routes: routes,
      trips: trips,
      stopTimes: stopTimes,
    );
  }

  static Map<String, GtfsStop> _parseStops(Archive archive) {
    final file = archive.findFile('stops.txt');
    if (file == null) return {};

    final content = String.fromCharCodes(file.content as List<int>);
    return _parseCsv(content, GtfsStop.fromCsv);
  }

  static Map<String, GtfsRoute> _parseRoutes(Archive archive) {
    final file = archive.findFile('routes.txt');
    if (file == null) return {};

    final content = String.fromCharCodes(file.content as List<int>);
    return _parseCsv(content, GtfsRoute.fromCsv);
  }

  static Map<String, GtfsTrip> _parseTrips(Archive archive) {
    final file = archive.findFile('trips.txt');
    if (file == null) return {};

    final content = String.fromCharCodes(file.content as List<int>);
    return _parseCsv(content, GtfsTrip.fromCsv);
  }

  static List<GtfsStopTime> _parseStopTimes(Archive archive) {
    final file = archive.findFile('stop_times.txt');
    if (file == null) return [];

    final content = String.fromCharCodes(file.content as List<int>);
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();

    if (lines.isEmpty) return [];

    final headers = _parseCsvLine(lines[0]);
    final stopTimes = <GtfsStopTime>[];

    for (var i = 1; i < lines.length; i++) {
      try {
        final values = _parseCsvLine(lines[i]);
        if (values.length >= headers.length) {
          stopTimes.add(GtfsStopTime.fromCsv(headers, values));
        }
      } catch (e) {
        // Skip malformed lines
      }
    }

    return stopTimes;
  }

  static Map<String, T> _parseCsv<T>(
    String content,
    T Function(List<String>, List<String>) factory,
  ) {
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return {};

    final headers = _parseCsvLine(lines[0]);
    final items = <String, T>{};

    for (var i = 1; i < lines.length; i++) {
      try {
        final values = _parseCsvLine(lines[i]);
        if (values.isNotEmpty) {
          final item = factory(headers, values);
          // Get ID from the item dynamically
          String? id;
          final dynamic dynamicItem = item;
          if (dynamicItem is GtfsRoute) {
            id = dynamicItem.routeId;
          } else if (dynamicItem is GtfsStop) {
            id = dynamicItem.stopId;
          } else if (dynamicItem is GtfsTrip) {
            id = dynamicItem.tripId;
          }
          if (id != null && id.isNotEmpty) {
            items[id] = item;
          }
        }
      } catch (e) {
        // Skip malformed lines silently
      }
    }

    return items;
  }

  static List<String> _parseCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        values.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    values.add(buffer.toString().trim());
    return values;
  }
}
