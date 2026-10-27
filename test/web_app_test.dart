import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:trufi_server_planner/web_app.dart';

/// Unit tests of the web-app pipeline (`createWebAppHandler`): the real
/// shelf_static handler over a temporary `web/` fixture, no network, so they
/// run in `dart test` without the server. The last group starts a real
/// `shelf_io` server on an ephemeral port to prove what goes on the wire.
void main() {
  late Directory webDir;
  late Handler handler;
  late List<int> mainJs;
  late List<int> indexHtml;

  Request request(
    String path, {
    String method = 'GET',
    Map<String, String>? headers,
  }) =>
      Request(method, Uri.parse('http://localhost$path'), headers: headers);

  Future<List<int>> bodyOf(Response response) async =>
      (await response.read().toList()).expand((chunk) => chunk).toList();

  setUpAll(() async {
    webDir = await Directory.systemTemp.createTemp('trufi-web-');
    final root = webDir.path;
    // dart2js-like text: large and compressible.
    mainJs = utf8.encode(
      List.generate(3000, (i) => 'function f$i(a,b){return a+b*$i;}\n').join(),
    );
    indexHtml = utf8.encode(
      '<!DOCTYPE html><html><head><title>Trufi Cochabamba</title>'
      '<!-- ${'padding ' * 100} --></head>'
      '<body><script src="flutter_bootstrap.js" async></script></body></html>',
    );
    await File('$root/index.html').writeAsBytes(indexHtml);
    await File('$root/main.dart.js').writeAsBytes(mainJs);
    await File('$root/main.dart.1a2b3c4d.js').writeAsBytes(mainJs);
    await File('$root/version.json').writeAsString(
      '{"app_name":"trufi","version":"5.4.0","build_number":"84",'
      '"package_name":"trufi"}',
    );
    // Pseudo-random bytes behind a .png name: an already-compressed type.
    await File('$root/favicon.png')
        .writeAsBytes(List.generate(4096, (i) => (i * 7919 + 13) & 0xff));
    await Directory('$root/assets/assets/search').create(recursive: true);
    await File('$root/assets/assets/search/search.json').writeAsString(
      jsonEncode(List.generate(
        500,
        (i) => {'name': 'Parada $i', 'lat': -17.39 + i / 1e3, 'lon': -66.15},
      )),
    );
    handler = createWebAppHandler(root);
  });

  tearDownAll(() => webDir.delete(recursive: true));

  group('gzip', () {
    test('GET with Accept-Encoding: gzip gets a smaller gzip body', () async {
      final response = await handler(request(
        '/main.dart.js',
        headers: {'accept-encoding': 'gzip, deflate, br'},
      ));
      expect(response.statusCode, 200);
      expect(response.headers['content-encoding'], 'gzip');
      expect(response.headers['vary'], 'Accept-Encoding');
      expect(response.headers['content-type'], 'text/javascript');
      expect(response.headers['etag'], isNotNull);
      expect(response.headers['accept-ranges'], isNull);

      final body = await bodyOf(response);
      expect(body.length, lessThan(mainJs.length ~/ 5));
      expect(response.headers['content-length'], '${body.length}');
      expect(gzip.decode(body), mainJs);
    });

    test('GET without Accept-Encoding gets the identity body', () async {
      final response = await handler(request('/main.dart.js'));
      expect(response.statusCode, 200);
      expect(response.headers['content-encoding'], isNull);
      expect(response.headers['content-length'], '${mainJs.length}');
      expect(response.headers['accept-ranges'], 'bytes');
      // Shared caches must still key on Accept-Encoding.
      expect(response.headers['vary'], 'Accept-Encoding');
      expect(await bodyOf(response), mainJs);
    });

    test('Accept-Encoding negotiation honours q values and wildcards', () {
      const cases = {
        'gzip': true,
        'GZIP': true,
        'x-gzip': true,
        'gzip, deflate, br': true,
        'deflate, gzip;q=0.5': true,
        '*': true,
        'identity, *;q=0.1': true,
        'br': false,
        'identity': false,
        'gzip;q=0, identity': false,
        'gzip;q=0, *': false,
        'identity;q=1, *;q=0': false,
      };
      for (final entry in cases.entries) {
        expect(
          acceptsGzip(request('/x', headers: {'accept-encoding': entry.key})),
          entry.value,
          reason: 'Accept-Encoding: ${entry.key}',
        );
      }
      expect(acceptsGzip(request('/x')), isFalse);
    });

    test('a client that only accepts br gets the identity body', () async {
      final response = await handler(
        request('/main.dart.js', headers: {'accept-encoding': 'br'}),
      );
      expect(response.headers['content-encoding'], isNull);
      expect(await bodyOf(response), mainJs);
    });

    test('bodies under 512 bytes stay identity', () async {
      final response = await handler(
        request('/version.json', headers: {'accept-encoding': 'gzip'}),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-encoding'], isNull);
      expect(response.headers['content-length'], '81');
    });

    test('already-compressed types (png) stay identity', () async {
      final response = await handler(
        request('/favicon.png', headers: {'accept-encoding': 'gzip'}),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'image/png');
      expect(response.headers['content-encoding'], isNull);
      expect(response.headers['content-length'], '4096');
    });

    test('JSON assets are compressed', () async {
      final response = await handler(request(
        '/assets/assets/search/search.json',
        headers: {'accept-encoding': 'gzip'},
      ));
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'application/json');
      expect(response.headers['content-encoding'], 'gzip');
      final original =
          await File('${webDir.path}/assets/assets/search/search.json')
              .readAsBytes();
      final body = await bodyOf(response);
      expect(body.length, lessThan(original.length ~/ 4));
      expect(gzip.decode(body), original);
    });

    test('a 304 revalidation is not re-encoded', () async {
      final first = await handler(
        request('/main.dart.js', headers: {'accept-encoding': 'gzip'}),
      );
      final etag = first.headers['etag']!;
      final response = await handler(request(
        '/main.dart.js',
        headers: {'accept-encoding': 'gzip', 'if-none-match': etag},
      ));
      expect(response.statusCode, 304);
      expect(response.headers['content-encoding'], isNull);
      // shelf stamps `content-length: 0` on any body-less response whose
      // headers are changed (corsMiddleware already did that on every 304);
      // what matters here is that it is not the size of a gzip body.
      expect(response.headers['content-length'], anyOf(isNull, '0'));
      expect(response.headers['etag'], etag);
      expect(response.headers['vary'], 'Accept-Encoding');
      expect(await bodyOf(response), isEmpty);
    });

    test('a 304 by If-Modified-Since is not re-encoded either', () async {
      final first = await handler(request('/main.dart.js'));
      final response = await handler(request(
        '/main.dart.js',
        headers: {
          'accept-encoding': 'gzip',
          'if-modified-since': first.headers['last-modified']!,
        },
      ));
      expect(response.statusCode, 304);
      expect(response.headers['content-encoding'], isNull);
      expect(response.headers['content-length'], anyOf(isNull, '0'));
    });

    test('range requests are answered with identity bytes', () async {
      final response = await handler(request(
        '/main.dart.js',
        headers: {'accept-encoding': 'gzip', 'range': 'bytes=0-99'},
      ));
      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes 0-99/${mainJs.length}');
      expect(response.headers['content-encoding'], isNull);
      expect(response.headers['content-length'], '100');
      expect(await bodyOf(response), mainJs.sublist(0, 100));
    });

    test('HEAD keeps the identity Content-Length and sends no body', () async {
      final response = await handler(request(
        '/main.dart.js',
        method: 'HEAD',
        headers: {'accept-encoding': 'gzip'},
      ));
      expect(response.statusCode, 200);
      expect(response.headers['content-encoding'], isNull);
      expect(response.headers['content-length'], '${mainJs.length}');
      expect(await bodyOf(response), isEmpty);
    });

    test('Vary is merged with an existing value', () async {
      Response stub(Request _) => Response.ok(
            'x' * 2048,
            headers: {'vary': 'Origin', 'content-type': 'text/plain'},
          );
      final response = await gzipStatic()(stub)(
        request('/x', headers: {'accept-encoding': 'gzip'}),
      );
      expect(response.headers['vary'], 'Origin, Accept-Encoding');
      expect(response.headers['content-encoding'], 'gzip');

      Response already(Request _) => Response.ok(
            'x' * 2048,
            headers: {'vary': 'accept-encoding'},
          );
      final kept = await gzipStatic()(already)(request('/x'));
      expect(kept.headers['vary'], 'accept-encoding');
    });
  });

  group('over HTTP', () {
    late HttpServer server;
    late Uri base;

    setUpAll(() async {
      server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://${server.address.host}:${server.port}');
    });

    tearDownAll(() => server.close(force: true));

    Future<(HttpClientResponse, List<int>)> fetch(
      String path, {
      bool autoUncompress = false,
      String? acceptEncoding,
    }) async {
      final client = HttpClient()..autoUncompress = autoUncompress;
      try {
        final req = await client.getUrl(base.resolve(path));
        // dart:io adds `Accept-Encoding: gzip` on its own, whatever
        // `autoUncompress` says: send exactly what the test asks for.
        req.headers.removeAll(HttpHeaders.acceptEncodingHeader);
        if (acceptEncoding != null) {
          req.headers.set(HttpHeaders.acceptEncodingHeader, acceptEncoding);
        }
        final res = await req.close();
        final bytes = (await res.toList()).expand((c) => c).toList();
        return (res, bytes);
      } finally {
        client.close(force: true);
      }
    }

    test('the wire carries gzip bytes with a matching Content-Length',
        () async {
      final (res, bytes) = await fetch('/main.dart.js', acceptEncoding: 'gzip');
      expect(res.statusCode, 200);
      expect(res.headers.value('content-encoding'), 'gzip');
      expect(res.headers.value('vary'), 'Accept-Encoding');
      expect(res.headers.contentLength, bytes.length);
      expect(bytes.length, lessThan(mainJs.length ~/ 5));
      expect(gzip.decode(bytes), mainJs);
    });

    test('the wire carries identity bytes without Accept-Encoding', () async {
      final (res, bytes) = await fetch('/main.dart.js');
      expect(res.statusCode, 200);
      expect(res.headers.value('content-encoding'), isNull);
      expect(res.headers.contentLength, mainJs.length);
      expect(bytes, mainJs);
    });

    test('a transparent client (dart:io default) sees the original bytes',
        () async {
      // HttpClient sends Accept-Encoding: gzip and decompresses by itself.
      final (res, bytes) = await fetch('/main.dart.js', autoUncompress: true);
      expect(res.statusCode, 200);
      expect(bytes, mainJs);
    });

    test('a 304 on the wire has no body and no Content-Encoding', () async {
      final (first, _) = await fetch('/main.dart.js');
      final client = HttpClient()..autoUncompress = false;
      try {
        final req = await client.getUrl(base.resolve('/main.dart.js'));
        req.headers
          ..set(HttpHeaders.acceptEncodingHeader, 'gzip')
          ..set(HttpHeaders.ifNoneMatchHeader, first.headers.value('etag')!);
        final res = await req.close();
        expect(res.statusCode, 304);
        expect(res.headers.value('content-encoding'), isNull);
        expect(await res.toList(), isEmpty);
      } finally {
        client.close(force: true);
      }
    });
  });
}
