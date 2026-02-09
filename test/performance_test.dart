import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

const baseUrl = 'http://localhost:9090';

void main() {
  group('Performance Tests', () {
    test('Health check response time', () async {
      final sw = Stopwatch()..start();
      final response = await http.get(Uri.parse('$baseUrl/health'));
      sw.stop();

      expect(response.statusCode, 200);
      expect(sw.elapsedMilliseconds, lessThan(1000),
          reason: 'Health check should respond in <1s');

      print('✓ Health check: ${sw.elapsedMilliseconds}ms');
    });

    test('Nearby stops search performance', () async {
      final sw = Stopwatch()..start();
      final response = await http.get(
        Uri.parse('$baseUrl/stops/nearby?lat=-17.3935&lon=-66.1570&maxResults=10'),
      );
      sw.stop();

      expect(response.statusCode, 200);
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'Spatial search should be <500ms');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      print('✓ Nearby stops: ${sw.elapsedMilliseconds}ms (${data['count']} results)');
    });

    test('Route planning performance', () async {
      final sw = Stopwatch()..start();
      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': {'lat': -17.3935, 'lon': -66.1570},
          'to': {'lat': -17.4000, 'lon': -66.1600},
        }),
      );
      sw.stop();

      expect(response.statusCode, 200);
      expect(sw.elapsedMilliseconds, lessThan(30000),
          reason: 'Route planning should be <30s');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success']) {
        print('✓ Route planning: ${sw.elapsedMilliseconds}ms (${data['count']} routes)');
      } else {
        print('✓ Route planning: ${sw.elapsedMilliseconds}ms (no routes)');
      }
    });

    test('Concurrent requests handling', () async {
      final sw = Stopwatch()..start();

      // Fire 10 concurrent requests
      final futures = List.generate(
        10,
        (_) => http.get(Uri.parse('$baseUrl/health')),
      );

      final responses = await Future.wait(futures);
      sw.stop();

      expect(responses.every((r) => r.statusCode == 200), true);
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: '10 concurrent requests should complete in <2s');

      print('✓ Concurrent requests (10): ${sw.elapsedMilliseconds}ms');
      print('  - Avg per request: ${sw.elapsedMilliseconds ~/ 10}ms');
    });

    test('List all routes performance', () async {
      final sw = Stopwatch()..start();
      final response = await http.get(Uri.parse('$baseUrl/routes'));
      sw.stop();

      expect(response.statusCode, 200);
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'Listing routes should be <500ms');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      print('✓ List routes: ${sw.elapsedMilliseconds}ms (${data['total']} routes)');
    });

    test('Sequential route planning (5 requests)', timeout: Timeout(Duration(minutes: 3)), () async {
      final coordinates = [
        {'from': {'lat': -17.3935, 'lon': -66.1570}, 'to': {'lat': -17.4000, 'lon': -66.1600}},
        {'from': {'lat': -17.3900, 'lon': -66.1600}, 'to': {'lat': -17.3950, 'lon': -66.1650}},
        {'from': {'lat': -17.3850, 'lon': -66.1550}, 'to': {'lat': -17.3950, 'lon': -66.1620}},
        {'from': {'lat': -17.3920, 'lon': -66.1580}, 'to': {'lat': -17.4020, 'lon': -66.1630}},
        {'from': {'lat': -17.3880, 'lon': -66.1590}, 'to': {'lat': -17.3980, 'lon': -66.1640}},
      ];

      final sw = Stopwatch()..start();
      int totalRoutes = 0;

      for (final coords in coordinates) {
        final response = await http.post(
          Uri.parse('$baseUrl/plan'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(coords),
        );

        expect(response.statusCode, 200);
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success']) {
          totalRoutes += (data['count'] as int);
        }
      }

      sw.stop();

      print('✓ Sequential planning (5 requests): ${sw.elapsedMilliseconds}ms');
      print('  - Avg per request: ${sw.elapsedMilliseconds ~/ 5}ms');
      print('  - Total routes found: $totalRoutes');
    });

    test('Memory efficiency - Large result sets', () async {
      final response = await http.get(Uri.parse('$baseUrl/stops?limit=1000'));

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final stops = data['stops'] as List;

      expect(stops.length, lessThanOrEqualTo(1000));
      print('✓ Large result set: ${stops.length} stops returned');
    });
  });
}
