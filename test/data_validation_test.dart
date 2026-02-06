import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

const baseUrl = 'http://localhost:9090';

void main() {
  group('Data Validation Tests', () {
    test('Stop data structure validation', () async {
      final response = await http.get(Uri.parse('$baseUrl/stops?limit=1'));

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final stops = data['stops'] as List;
      expect(stops.length, greaterThan(0));

      final stop = stops[0] as Map<String, dynamic>;

      // Validate required fields
      expect(stop['id'], isNotNull);
      expect(stop['name'], isNotNull);
      expect(stop['lat'], isA<num>());
      expect(stop['lon'], isA<num>());

      // Validate coordinate ranges (Cochabamba)
      expect(stop['lat'], inInclusiveRange(-17.5, -17.3));
      expect(stop['lon'], inInclusiveRange(-66.3, -66.0));

      print('✓ Stop data structure valid');
      print('  - ID: ${stop['id']}');
      print('  - Name: ${stop['name']}');
      print('  - Coordinates: (${stop['lat']}, ${stop['lon']})');
    });

    test('Route data structure validation', () async {
      final response = await http.get(Uri.parse('$baseUrl/routes'));

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List;
      expect(routes.length, greaterThan(0));

      final route = routes[0] as Map<String, dynamic>;

      // Validate required fields
      expect(route['id'], isNotNull);
      expect(route['shortName'], isNotNull);
      expect(route['longName'], isNotNull);
      expect(route['type'], isNotNull);

      // Validate route type is valid GTFS type
      final typeStr = route['type'] as String;
      final type = int.tryParse(typeStr);
      expect(type, isNotNull);
      expect(type, inInclusiveRange(0, 12)); // Valid GTFS route types

      print('✓ Route data structure valid');
      print('  - Short name: ${route['shortName']}');
      print('  - Long name: ${route['longName']}');
      print('  - Type: ${route['type']}');
    });

    test('Path data structure validation', () async {
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
        expect(paths.length, greaterThan(0));

        final path = paths[0] as Map<String, dynamic>;

        // Validate path structure
        expect(path['originWalk'], isA<num>());
        expect(path['destinationWalk'], isA<num>());
        expect(path['totalWalk'], isA<num>());
        expect(path['transfers'], isA<int>());
        expect(path['totalStops'], isA<int>());
        expect(path['score'], isA<num>());

        // Validate stops
        expect(path['originStop'], isNotNull);
        expect(path['destinationStop'], isNotNull);

        // Validate segments
        final segments = path['segments'] as List;
        expect(segments.length, greaterThan(0));

        final segment = segments[0] as Map<String, dynamic>;
        expect(segment['route'], isNotNull);
        expect(segment['from'], isNotNull);
        expect(segment['to'], isNotNull);
        expect(segment['stopCount'], isA<int>());
        expect(segment['stopCount'], greaterThan(0));

        // Validate calculations
        final originWalk = path['originWalk'] as num;
        final destWalk = path['destinationWalk'] as num;
        final totalWalk = path['totalWalk'] as num;
        expect(totalWalk, equals(originWalk + destWalk));

        print('✓ Path data structure valid');
        print('  - Segments: ${segments.length}');
        print('  - Total stops: ${path['totalStops']}');
        print('  - Walk distances sum correctly');
      } else {
        print('✓ No routes found (skipping validation)');
      }
    });

    test('Distance calculations accuracy', () async {
      final response = await http.get(
        Uri.parse('$baseUrl/stops/nearby?lat=-17.3935&lon=-66.1570&maxResults=5&maxDistance=500'),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final stops = data['stops'] as List;

      for (final stopData in stops) {
        final stop = stopData as Map<String, dynamic>;
        final distance = stop['distance'] as num;

        // All distances should be within requested radius
        expect(distance, lessThanOrEqualTo(500));
        expect(distance, greaterThanOrEqualTo(0));
      }

      // Distances should be in ascending order
      for (var i = 0; i < stops.length - 1; i++) {
        final dist1 = (stops[i] as Map)['distance'] as num;
        final dist2 = (stops[i + 1] as Map)['distance'] as num;
        expect(dist1, lessThanOrEqualTo(dist2),
            reason: 'Stops should be ordered by distance');
      }

      print('✓ Distance calculations accurate');
      print('  - All distances within 500m');
      print('  - Results sorted by distance');
    });

    test('Route scoring consistency', () async {
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

        // Scores should be in ascending order (lower is better)
        for (var i = 0; i < paths.length - 1; i++) {
          final score1 = (paths[i] as Map)['score'] as num;
          final score2 = (paths[i + 1] as Map)['score'] as num;
          expect(score1, lessThanOrEqualTo(score2),
              reason: 'Routes should be sorted by score');
        }

        print('✓ Route scoring consistent');
        print('  - ${paths.length} routes sorted by score');
        print('  - Best score: ${(paths[0] as Map)['score']}');
      }
    });

    test('HTTP headers validation', () async {
      final response = await http.get(Uri.parse('$baseUrl/health'));

      expect(response.statusCode, 200);

      // Check important headers
      expect(response.headers['content-type'], contains('application/json'));
      expect(response.headers['access-control-allow-origin'], '*');

      print('✓ HTTP headers valid');
      print('  - Content-Type: ${response.headers['content-type']}');
      print('  - CORS enabled');
    });

    test('JSON response format validation', () async {
      final endpoints = [
        '/health',
        '/stops?limit=1',
        '/routes',
        '/stops/nearby?lat=-17.3935&lon=-66.1570',
      ];

      for (final endpoint in endpoints) {
        final response = await http.get(Uri.parse('$baseUrl$endpoint'));

        expect(response.statusCode, 200);

        // Should be valid JSON
        expect(() => jsonDecode(response.body), returnsNormally);

        final data = jsonDecode(response.body);
        expect(data, isA<Map<String, dynamic>>());
      }

      print('✓ All endpoints return valid JSON');
    });

    test('Error response format validation', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': {'lat': -17.3935}, // Missing lon
        }),
      );

      expect(response.statusCode, 400);

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['error'], isNotNull);
      expect(data['error'], isA<String>());

      print('✓ Error responses properly formatted');
      print('  - Error message: ${data['error']}');
    });
  });
}
