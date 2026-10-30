import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:trufi_core_planner/trufi_core_planner.dart';
import 'package:trufi_server_planner/handlers/docs.dart';
import 'package:trufi_server_planner/handlers/plan.dart';
import 'package:trufi_server_planner/state.dart';

/// Unit tests of the `/plan` handler: the committed Cochabamba feed loaded
/// in-process (what `bin/server.dart` does at start-up) and the handler
/// called with a hand-built shelf `Request` — no server, no network.
void main() {
  // Two pairs of the example feed whose answer depends on the knobs
  // (probed on trufi_core_planner v5.27.0): [docsExample] has six direct
  // lines with the default pool of 150 stops, twelve with 600 and none
  // with 1; [northEast] has no direct line and fifteen one-transfer paths;
  // [farWest] has nothing with 0 or 1 transfers and twenty 2-transfer
  // paths (found by the fresh review of PR #10); [downtown] has more than
  // 600 stops within 800 m of both ends and answers with twenty direct
  // lines, among which the 33 (Trufi 121) only once the pool reaches 800
  // (the stops ranked 601-800; sweep of the cap PR, trufi-app#71's value).
  const docsExample = {
    'from': {'lat': -17.420536, 'lon': -66.143176},
    'to': {'lat': -17.384842, 'lon': -66.147902},
  };
  const northEast = {
    'from': {'lat': -17.3600, 'lon': -66.1700},
    'to': {'lat': -17.4100, 'lon': -66.1300},
  };
  const farWest = {
    'from': {'lat': -17.535196, 'lon': -66.3354927},
    'to': {'lat': -17.4013699, 'lon': -66.0613446},
  };
  const downtown = {
    'from': {'lat': -17.3878387, 'lon': -66.1644142},
    'to': {'lat': -17.4049692, 'lon': -66.1508767},
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

    test('maxTransfers 2 reaches a pair that has no 0/1-transfer path, '
        'and 9 is the planner at the cap', () async {
      final (_, one) = await plan(farWest);
      final (_, two) = await plan(farWest, {'maxTransfers': 2});
      final (_, atCap) = await plan(farWest, {'maxTransfers': maxTransfersCap});
      final (_, nine) = await plan(farWest, {'maxTransfers': 9});

      expect(one['success'], false);
      expect(two['success'], true);
      expect(
        (two['paths'] as List).map((p) => p['transfers']),
        everyElement(2),
      );
      expect(nine['effectiveParameters']['maxTransfers'], maxTransfersCap);
      expect(lines(nine), lines(atCap));
      expect(lines(nine), isNotEmpty);
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
        'reported as true and listed in ignoredParameters, same '
        'itineraries', () async {
      // trufi_core_planner v5.27.0 has no such parameter (trufi-core#1043
      // is not released): this test flips when the pin is bumped and the
      // handler forwards the knob.
      final (_, none) = await plan(docsExample);
      final (status, json) = await plan(docsExample, {
        'directsHideTransfers': false,
      });
      expect(status, 200);
      expect(json['effectiveParameters']['directsHideTransfers'], true);
      expect(json['ignoredParameters'], ['directsHideTransfers']);
      expect(lines(json), lines(none));
    });

    test('ignoredParameters is absent when nothing was ignored', () async {
      final (_, none) = await plan(docsExample);
      final (_, sentTrue) = await plan(docsExample, {
        'directsHideTransfers': true,
      });
      final (_, sentNull) = await plan(docsExample, {
        'directsHideTransfers': null,
      });
      expect(none.containsKey('ignoredParameters'), isFalse);
      expect(sentTrue.containsKey('ignoredParameters'), isFalse);
      expect(sentNull.containsKey('ignoredParameters'), isFalse);
    });

    test('a "no routes" answer lists the ignored knob too', () async {
      final (status, json) = await plan(docsExample, {
        'maxStopCandidates': 1,
        'directsHideTransfers': false,
      });
      expect(status, 200);
      expect(json['success'], false);
      expect(json['ignoredParameters'], ['directsHideTransfers']);
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

    test(
      'maxResults and maxWalkDistance clamp on both sides (#4 rule kept)',
      () async {
        final (_, low) = await plan(docsExample, {
          'maxResults': 0,
          'maxWalkDistance': 5,
        });
        final (_, high) = await plan(docsExample, {
          'maxResults': 50,
          'maxWalkDistance': 5000,
        });
        final (_, fraction) = await plan(docsExample, {'maxResults': 2.7});
        expect(low['effectiveParameters']['maxResults'], 1);
        expect(low['effectiveParameters']['maxWalkDistance'], 100.0);
        expect(high['effectiveParameters']['maxResults'], 20);
        expect(high['effectiveParameters']['maxWalkDistance'], 2000.0);
        expect(fraction['effectiveParameters']['maxResults'], 2);
      },
    );

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

    test('an integral value beyond int64 is an integer: clamped, not '
        'rejected, however it is spelled', () async {
      for (final literal in ['1e19', '9223372036854775808']) {
        final (status, json) = await post(
          '{"from":{"lat":-17.420536,"lon":-66.143176},'
          '"to":{"lat":-17.384842,"lon":-66.147902},'
          '"maxStopCandidates":$literal}',
        );
        expect(status, 200, reason: literal);
        expect(
          json['effectiveParameters']['maxStopCandidates'],
          maxStopCandidatesCap,
          reason: literal,
        );
      }
      final (status, json) = await post(
        '{"from":{"lat":-17.420536,"lon":-66.143176},'
        '"to":{"lat":-17.384842,"lon":-66.147902},"maxStopCandidates":-1e19}',
      );
      expect(status, 400);
      expect(json['error'], 'maxStopCandidates must be >= 1');
    });

    test('the cap is at least the pool trufi-app sends, and that pool runs '
        'as sent', () async {
      // trufi-app#71: 800, the first round number above the 778 stops the
      // densest point of Cochabamba has within the app's 800 m walking
      // radius. Clamping it would make the web differ from the phone on
      // the trips that need the stops ranked 601-778.
      expect(maxStopCandidatesCap, greaterThanOrEqualTo(800));
      final (status, json) = await plan(docsExample, {
        'maxStopCandidates': 800,
      });
      expect(status, 200);
      expect(json['effectiveParameters']['maxStopCandidates'], 800);
    });

    test('the stops ranked 601-800 bring a line into a downtown answer that '
        '600 does not offer', () async {
      final (_, at600) = await plan(downtown, {'maxStopCandidates': 600});
      final (_, at800) = await plan(downtown, {'maxStopCandidates': 800});
      expect(at600['success'], true);
      expect(at800['success'], true);
      expect(at800['effectiveParameters']['maxStopCandidates'], 800);
      expect(lines(at600), isNot(contains('33')));
      expect(lines(at800), contains('33'));
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
      'maxResults': [
        '20',
        true,
        [20],
      ],
      'maxWalkDistance': [
        '800',
        false,
        {'m': 800},
      ],
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

    test('1e400 is not a number for the clamped fields either', () async {
      final (status, json) = await post(
        '{"from":{"lat":-17.420536,"lon":-66.143176},'
        '"to":{"lat":-17.384842,"lon":-66.147902},"maxWalkDistance":1e400}',
      );
      expect(status, 400);
      expect(json['error'], 'maxWalkDistance must be a number');
    });

    test('the message says what was expected', () async {
      final (_, notInt) = await plan(docsExample, {'maxStopCandidates': '5'});
      final (_, tooLow) = await plan(docsExample, {'maxStopCandidates': 0});
      final (_, negative) = await plan(docsExample, {'maxTransfers': -1});
      final (_, notBool) = await plan(docsExample, {
        'directsHideTransfers': 'yes',
      });
      final (_, notNum) = await plan(docsExample, {'maxResults': '20'});
      final (_, notNumWalk) = await plan(docsExample, {
        'maxWalkDistance': '800',
      });
      expect(notInt['error'], 'maxStopCandidates must be an integer');
      expect(tooLow['error'], 'maxStopCandidates must be >= 1');
      expect(negative['error'], 'maxTransfers must be >= 0');
      expect(notBool['error'], 'directsHideTransfers must be a boolean');
      expect(notNum['error'], 'maxResults must be a number');
      expect(notNumWalk['error'], 'maxWalkDistance must be a number');
    });

    test(
      'several invalid fields: the first in reading order is reported',
      () async {
        final (_, knobs) = await plan(docsExample, {
          'maxTransfers': -1,
          'maxStopCandidates': 0,
        });
        final (_, clamped) = await plan(docsExample, {
          'maxStopCandidates': 0,
          'maxResults': '20',
        });
        expect(knobs['error'], 'maxStopCandidates must be >= 1');
        expect(clamped['error'], 'maxResults must be a number');
      },
    );

    test('missing coordinates win over an invalid knob', () async {
      final (status, json) = await post(
        jsonEncode({
          'from': {'lat': -17.3935},
          'maxTransfers': -1,
        }),
      );
      expect(status, 400);
      expect(json['error'], 'Missing from/to coordinates');
    });
  });

  group('openapi', () {
    test(
      '/api/openapi.json documents the knobs, the caps and both responses',
      () async {
        final response = openApiSpecHandler(
          Request('GET', Uri.parse('http://localhost/api/openapi.json')),
        );
        expect(response.statusCode, 200);
        final spec =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        final post = spec['paths']['/plan']['post'] as Map<String, dynamic>;
        final properties =
            post['requestBody']['content']['application/json']['schema']['properties']
                as Map<String, dynamic>;
        expect(
          properties.keys,
          containsAll([
            'from',
            'to',
            'maxResults',
            'maxWalkDistance',
            'maxStopCandidates',
            'maxTransfers',
            'directsHideTransfers',
          ]),
        );
        expect(
          properties['maxStopCandidates']['description'],
          contains('1-$maxStopCandidatesCap'),
        );
        expect(
          properties['maxTransfers']['description'],
          contains('0-$maxTransfersCap'),
        );
        expect(
          properties['directsHideTransfers']['description'],
          contains('ignoredParameters'),
        );
        final responses = post['responses'] as Map<String, dynamic>;
        expect(responses.keys, containsAll(['200', '400']));
        expect(
          responses['200']['description'],
          allOf(contains('effectiveParameters'), contains('ignoredParameters')),
        );
        expect(responses['400']['description'], contains('maxResults'));
      },
    );
  });
}
