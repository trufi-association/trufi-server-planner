import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

const baseUrl = 'http://localhost:9090';

void main() {
  group('Trufi Server Planner Integration Tests', () {
    test('Health check returns status and GTFS data', () async {
      final response = await http.get(Uri.parse('$baseUrl/health'));

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      expect(data['status'], 'healthy');
      expect(data['service'], 'trufi-server-planner');
      expect(data['gtfs'], isNotNull);
      expect(data['gtfs']['stops'], greaterThan(0));
      expect(data['gtfs']['routes'], greaterThan(0));
      expect(data['gtfs']['trips'], greaterThan(0));

      print('✓ Health check passed');
      print('  - ${data['gtfs']['stops']} stops');
      print('  - ${data['gtfs']['routes']} routes');
      print('  - ${data['gtfs']['trips']} trips');
    });

    test('List stops returns data', () async {
      final response = await http.get(Uri.parse('$baseUrl/stops?limit=5'));

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      expect(data['stops'], isList);
      expect(data['total'], greaterThan(0));

      final stops = data['stops'] as List;
      expect(stops.length, lessThanOrEqualTo(5));

      if (stops.isNotEmpty) {
        final stop = stops[0] as Map<String, dynamic>;
        expect(stop['id'], isNotNull);
        expect(stop['name'], isNotNull);
        expect(stop['lat'], isNotNull);
        expect(stop['lon'], isNotNull);
      }

      print('✓ List stops passed');
      print('  - Found ${stops.length} stops');
    });

    test('Find nearby stops works', () async {
      // Cochabamba city center coordinates
      final lat = -17.3935;
      final lon = -66.1570;

      final response = await http.get(
        Uri.parse('$baseUrl/stops/nearby?lat=$lat&lon=$lon&maxResults=5&maxDistance=500'),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      expect(data['stops'], isList);
      expect(data['count'], greaterThan(0));

      final stops = data['stops'] as List;
      expect(stops.length, greaterThan(0));

      // Check first stop has distance
      final firstStop = stops[0] as Map<String, dynamic>;
      expect(firstStop['distance'], isNotNull);
      expect(firstStop['distance'], lessThanOrEqualTo(500));
      expect(firstStop['stop'], isNotNull);
      expect(firstStop['stop']['name'], isNotNull);

      print('✓ Nearby stops passed');
      print('  - Found ${stops.length} stops within 500m');
      print('  - Closest: ${firstStop['stop']['name']} at ${firstStop['distance']}m');
    });

    test('List routes returns data', () async {
      final response = await http.get(Uri.parse('$baseUrl/routes'));

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      expect(data['routes'], isList);
      expect(data['total'], greaterThan(0));

      final routes = data['routes'] as List;
      expect(routes.length, greaterThan(0));

      final route = routes[0] as Map<String, dynamic>;
      expect(route['id'], isNotNull);
      expect(route['shortName'], isNotNull);
      expect(route['longName'], isNotNull);

      print('✓ List routes passed');
      print('  - Found ${routes.length} routes');
      print('  - First route: ${route['shortName']} - ${route['longName']}');
    });

    test('Plan route finds paths', () async {
      final requestBody = jsonEncode({
        'from': {'lat': -17.3935, 'lon': -66.1570},
        'to': {'lat': -17.4000, 'lon': -66.1600},
      });

      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      expect(data['success'], true);
      expect(data['paths'], isList);
      expect(data['count'], greaterThan(0));

      final paths = data['paths'] as List;
      expect(paths.length, greaterThan(0));

      // Check first path structure
      final path = paths[0] as Map<String, dynamic>;
      expect(path['originWalk'], isNotNull);
      expect(path['originStop'], isNotNull);
      expect(path['segments'], isList);
      expect(path['destinationStop'], isNotNull);
      expect(path['destinationWalk'], isNotNull);
      expect(path['totalWalk'], isNotNull);
      expect(path['transfers'], isNotNull);
      expect(path['totalStops'], greaterThan(0));

      // Check segment structure
      final segments = path['segments'] as List;
      expect(segments.length, greaterThan(0));

      final segment = segments[0] as Map<String, dynamic>;
      expect(segment['route'], isNotNull);
      expect(segment['from'], isNotNull);
      expect(segment['to'], isNotNull);
      expect(segment['stopCount'], greaterThan(0));

      print('✓ Plan route passed');
      print('  - Found ${paths.length} paths');
      print('  - First route: ${segment['route']['shortName']} (${segment['stopCount']} stops)');
      print('  - Walk: ${path['originWalk']}m + ${path['destinationWalk']}m = ${path['totalWalk']}m');
      print('  - Transfers: ${path['transfers']}');
    });

    test('Plan route handles missing coordinates', () async {
      final requestBody = jsonEncode({
        'from': {'lat': -17.3935},
        // Missing 'to' coordinates
      });

      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      expect(response.statusCode, 400);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['error'], isNotNull);

      print('✓ Error handling passed');
      print('  - Correctly rejects invalid input');
    });

    test('Web app serves HTML', () async {
      final response = await http.get(Uri.parse('$baseUrl/'));

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('text/html'));
      expect(response.body, contains('Trufi'));

      print('✓ Web app passed');
      print('  - HTML page served correctly');
    });

    test('CORS headers are present', () async {
      final response = await http.get(Uri.parse('$baseUrl/health'));

      expect(response.headers['access-control-allow-origin'], '*');
      expect(response.headers['access-control-allow-methods'], isNotNull);

      print('✓ CORS passed');
      print('  - CORS headers present');
    });
  });
}
