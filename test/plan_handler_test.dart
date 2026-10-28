import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:trufi_core_planner/trufi_core_planner.dart';
import 'package:trufi_server_planner/handlers/plan.dart';
import 'package:trufi_server_planner/state.dart';

/// Unit tests of the `/plan` handler: the committed Cochabamba feed loaded
/// in-process (what `bin/server.dart` does at start-up) and the handler
/// called with a hand-built shelf `Request` — no server, no network.
void main() {
  // Two pairs of the example feed whose answer depends on the knobs
  // (probed on trufi_core_planner v5.27.0): [docsExample] has six direct
  // lines with the default pool of 150 stops, twelve with 600 and none
  // with 1; [northEast] has no direct line and fifteen one-transfer paths.
  const docsExample = {
    'from': {'lat': -17.420536, 'lon': -66.143176},
    'to': {'lat': -17.384842, 'lon': -66.147902},
  };
  const northEast = {
    'from': {'lat': -17.3600, 'lon': -66.1700},
    'to': {'lat': -17.4100, 'lon': -66.1300},
  };
  const defaults = {
    'maxResults': 20,
    'maxWalkDistance': 800.0,
    'maxStopCandidates': 150,
    'maxTransfers': 1,
    'directsHideTransfers': true,
  };

  setUpAll(() async {
    gtfsData = await GtfsParser.parseFromFile('example.gtfs.zip');
    spatialIndex = GtfsSpatialIndex(gtfsData.stops);
    routeIndex = GtfsRouteIndex(gtfsData);
    routingService = GtfsRoutingService(
      data: gtfsData,
      spatialIndex: spatialIndex,
      routeIndex: routeIndex,
    );
  });

  Future<(int, Map<String, dynamic>)> post(String body) async {
    final response = await planHandler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/plan'),
        headers: {'content-type': 'application/json'},
        body: body,
      ),
    );
    expect(response.headers['content-type'], startsWith('application/json'));
    final json =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    return (response.statusCode, json);
  }

  Future<(int, Map<String, dynamic>)> plan(
    Map<String, Object?> pair, [
    Map<String, Object?> knobs = const {},
  ]) => post(jsonEncode({...pair, ...knobs}));

  /// The lines of every path, in order ("routeId" or "routeId>routeId"):
  /// the derived signal the tests compare instead of trusting a count.
  List<String> lines(Map<String, dynamic> json) => [
    for (final path in (json['paths'] as List? ?? const []))
      (path['segments'] as List)
          .map((segment) => segment['route']['id'])
          .join('>'),
  ];

  group('absent', () {
    test(
      'no knobs: planner defaults, reported in effectiveParameters',
      () async {
        final (status, json) = await plan(docsExample);
        expect(status, 200);
        expect(json['success'], true);
        expect(json['count'], greaterThan(0));
        expect(json['effectiveParameters'], defaults);
      },
    );

    test('null knobs count as absent', () async {
      final (status, json) = await plan(docsExample, {
        'maxStopCandidates': null,
        'maxTransfers': null,
        'directsHideTransfers': null,
      });
      expect(status, 200);
      expect(json['effectiveParameters'], defaults);
    });

    test('explicit defaults give the same itineraries as no knobs', () async {
      final (_, none) = await plan(docsExample);
      final (_, explicit) = await plan(docsExample, {
        'maxStopCandidates': 150,
        'maxTransfers': 1,
        'directsHideTransfers': true,
      });
      expect(lines(explicit), lines(none));
      expect(lines(none), isNotEmpty);
    });

    test('a "no routes" answer carries effectiveParameters too', () async {
      final (status, json) = await plan(docsExample, {'maxStopCandidates': 1});
      expect(status, 200);
      expect(json['success'], false);
      expect(json['paths'], isNull);
      expect(json['effectiveParameters'], {
        ...defaults,
        'maxStopCandidates': 1,
      });
    });
  });

  group('valid', () {
    test('maxStopCandidates widens the pool: 600 is a superset of 150, '
        '1 finds nothing', () async {
      final (_, at150) = await plan(docsExample);
      final (_, at600) = await plan(docsExample, {'maxStopCandidates': 600});
      final (_, at1) = await plan(docsExample, {'maxStopCandidates': 1});

      expect(at600['effectiveParameters']['maxStopCandidates'], 600);
      expect(lines(at600).length, greaterThan(lines(at150).length));
      expect(lines(at600), containsAll(lines(at150)));
      expect(at1['success'], false);
      expect(lines(at1), isEmpty);
    });

    test('maxTransfers 0 returns direct lines only', () async {
      final (_, oneTransfer) = await plan(northEast);
      final (_, direct) = await plan(northEast, {'maxTransfers': 0});

      expect(oneTransfer['success'], true);
      expect(
        (oneTransfer['paths'] as List).map((p) => p['transfers']),
        everyElement(1),
      );
      expect(direct['effectiveParameters']['maxTransfers'], 0);
      expect(direct['success'], false);
      expect(lines(direct), isEmpty);
    });

    test('values inside the range are honoured as sent', () async {
      final (status, json) = await plan(northEast, {
        'maxStopCandidates': 600,
        'maxTransfers': 4,
      });
      expect(status, 200);
      expect(json['effectiveParameters'], {
        ...defaults,
        'maxStopCandidates': 600,
        'maxTransfers': 4,
      });
    });

    test(
      'an integral double is an integer (JSON has one number type)',
      () async {
        final (status, json) = await plan(docsExample, {
          'maxStopCandidates': 600.0,
          'maxTransfers': 2.0,
        });
        expect(status, 200);
        expect(json['effectiveParameters']['maxStopCandidates'], 600);
        expect(json['effectiveParameters']['maxTransfers'], 2);
      },
    );

    test('directsHideTransfers false is accepted but not applied yet: '
        'reported as true, same itineraries', () async {
      // trufi_core_planner v5.27.0 has no such parameter (trufi-core#1043
      // is not released): this test flips when the pin is bumped and the
      // handler forwards the knob.
      final (_, none) = await plan(docsExample);
      final (status, json) = await plan(docsExample, {
        'directsHideTransfers': false,
      });
      expect(status, 200);
      expect(json['effectiveParameters']['directsHideTransfers'], true);
      expect(lines(json), lines(none));
    });
  });

  group('capped', () {
    test('above the cap is clamped to the cap, not rejected', () async {
      final (status, json) = await plan(docsExample, {
        'maxStopCandidates': 5000,
        'maxTransfers': 9,
        'maxResults': 50,
      });
      expect(status, 200);
      expect(json['success'], true);
      expect(json['effectiveParameters'], {
        ...defaults,
        'maxStopCandidates': maxStopCandidatesCap,
        'maxTransfers': maxTransfersCap,
        'maxResults': 20,
      });
    });

    test('the cap itself is honoured as sent', () async {
      final (status, json) = await plan(docsExample, {
        'maxStopCandidates': maxStopCandidatesCap,
        'maxTransfers': maxTransfersCap,
      });
      expect(status, 200);
      expect(
        json['effectiveParameters']['maxStopCandidates'],
        maxStopCandidatesCap,
      );
      expect(json['effectiveParameters']['maxTransfers'], maxTransfersCap);
    });
  });

  group('invalid', () {
    const cases = <String, List<Object?>>{
      'maxStopCandidates': [
        0,
        -3,
        '150',
        1.5,
        true,
        [150],
      ],
      'maxTransfers': [
        -1,
        '1',
        2.5,
        false,
        {'value': 1},
      ],
      'directsHideTransfers': ['false', 'true', 0, 1, 1.0],
    };

    for (final MapEntry(key: field, value: values) in cases.entries) {
      for (final value in values) {
        test('$field: ${jsonEncode(value)} → 400 naming the field', () async {
          final (status, json) = await plan(docsExample, {field: value});
          expect(status, 400);
          expect(json['error'], contains(field));
          expect(json.containsKey('paths'), isFalse);
          expect(json.containsKey('effectiveParameters'), isFalse);
        });
      }
    }

    test('a number too large for a double is not an integer', () async {
      // jsonDecode turns 1e400 into double.infinity; toInt() would throw.
      final (status, json) = await post(
        '{"from":{"lat":-17.420536,"lon":-66.143176},'
        '"to":{"lat":-17.384842,"lon":-66.147902},"maxTransfers":1e400}',
      );
      expect(status, 400);
      expect(json['error'], 'maxTransfers must be an integer');
    });

    test('the message says what was expected', () async {
      final (_, notInt) = await plan(docsExample, {'maxStopCandidates': '5'});
      final (_, tooLow) = await plan(docsExample, {'maxStopCandidates': 0});
      final (_, negative) = await plan(docsExample, {'maxTransfers': -1});
      final (_, notBool) = await plan(docsExample, {
        'directsHideTransfers': 'yes',
      });
      expect(notInt['error'], 'maxStopCandidates must be an integer');
      expect(tooLow['error'], 'maxStopCandidates must be >= 1');
      expect(negative['error'], 'maxTransfers must be >= 0');
      expect(notBool['error'], 'directsHideTransfers must be a boolean');
    });

    test('missing coordinates are still a 400', () async {
      final (status, json) = await post(
        jsonEncode({
          'from': {'lat': -17.3935},
          'maxTransfers': 2,
        }),
      );
      expect(status, 400);
      expect(json['error'], 'Missing from/to coordinates');
    });
  });
}
