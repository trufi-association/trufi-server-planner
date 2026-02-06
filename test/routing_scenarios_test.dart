import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

const baseUrl = 'http://localhost:9090';

void main() {
  group('Routing Scenarios Tests', () {
    test('Plan 1: Centro to Zona Sur', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': {'lat': -17.3935, 'lon': -66.1570}, // Centro
          'to': {'lat': -17.4200, 'lon': -66.1650}, // Zona Sur
        }),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['success']) {
        final paths = data['paths'] as List;
        expect(paths.length, greaterThan(0));

        print('✓ Plan 1: Centro → Zona Sur');
        print('  - Found ${paths.length} routes');
        if (paths.isNotEmpty) {
          final path = paths[0] as Map<String, dynamic>;
          print('  - Walk: ${path['totalWalk']}m');
          print('  - Transfers: ${path['transfers']}');
        }
      } else {
        print('✓ Plan 1: No routes available (expected for distant locations)');
      }
    });

    test('Plan 2: Plaza 14 de Septiembre to Universidad', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': {'lat': -17.3895, 'lon': -66.1568}, // Plaza
          'to': {'lat': -17.3700, 'lon': -66.1500}, // Universidad zona
        }),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      print('✓ Plan 2: Plaza → Universidad');
      if (data['success']) {
        final paths = data['paths'] as List;
        print('  - Found ${paths.length} routes');
      } else {
        print('  - No routes found');
      }
    });

    test('Plan 3: Short distance (walking viable)', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': {'lat': -17.3935, 'lon': -66.1570},
          'to': {'lat': -17.3945, 'lon': -66.1580}, // ~200m away
        }),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      print('✓ Plan 3: Short distance (~200m)');
      if (data['success']) {
        final paths = data['paths'] as List;
        print('  - Found ${paths.length} routes');
        if (paths.isNotEmpty) {
          final path = paths[0] as Map<String, dynamic>;
          print('  - Total walk: ${path['totalWalk']}m (mostly walking)');
        }
      } else {
        print('  - No transit routes (walking preferred)');
      }
    });

    test('Plan 4: Avenida Blanco Galindo corridor', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': {'lat': -17.3900, 'lon': -66.2000},
          'to': {'lat': -17.3950, 'lon': -66.1800},
        }),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      print('✓ Plan 4: Blanco Galindo corridor');
      if (data['success']) {
        final paths = data['paths'] as List;
        expect(paths.length, greaterThan(0));
        print('  - Found ${paths.length} routes (high transit corridor)');
      }
    });

    test('Plan 5: North to Center', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': {'lat': -17.3700, 'lon': -66.1600},
          'to': {'lat': -17.3935, 'lon': -66.1570},
        }),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      print('✓ Plan 5: North → Center');
      if (data['success']) {
        final paths = data['paths'] as List;
        print('  - Found ${paths.length} routes');
      }
    });

    test('Plan 6: Multiple route options comparison', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': {'lat': -17.3935, 'lon': -66.1570},
          'to': {'lat': -17.4000, 'lon': -66.1600},
        }),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['success']) {
        final paths = data['paths'] as List;
        expect(paths.length, greaterThan(1), reason: 'Should find multiple routes');

        print('✓ Plan 6: Multiple options available');
        print('  - Comparing ${paths.length} routes:');

        for (var i = 0; i < paths.length && i < 3; i++) {
          final path = paths[i] as Map<String, dynamic>;
          final segment = (path['segments'] as List)[0] as Map<String, dynamic>;
          final route = segment['route'] as Map<String, dynamic>;

          print('    Route ${i + 1}: ${route['shortName']} - '
              'Walk: ${path['totalWalk']}m, '
              'Stops: ${path['totalStops']}, '
              'Score: ${path['score']}');
        }
      }
    });

    test('Plan 7: Edge case - Very long distance', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': {'lat': -17.3500, 'lon': -66.1000},
          'to': {'lat': -17.4500, 'lon': -66.2000}, // ~15km away
        }),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      print('✓ Plan 7: Very long distance (~15km)');
      if (data['success']) {
        print('  - Found routes (impressive!)');
      } else {
        print('  - No routes (expected for very long distances)');
        expect(data['error'], isNotNull);
      }
    });

    test('Plan 8: Same origin and destination', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': {'lat': -17.3935, 'lon': -66.1570},
          'to': {'lat': -17.3935, 'lon': -66.1570}, // Same location
        }),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      print('✓ Plan 8: Same location');
      if (!data['success']) {
        print('  - Correctly reports no route needed');
      }
    });
  });
}
