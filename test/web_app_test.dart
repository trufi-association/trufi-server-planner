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
  }) => Request(method, Uri.parse('http://localhost$path'), headers: headers);

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
    await File(
      '$root/favicon.png',
    ).writeAsBytes(List.generate(4096, (i) => (i * 7919 + 13) & 0xff));
    await Directory('$root/assets/assets/search').create(recursive: true);
    await File('$root/assets/assets/search/search.json').writeAsString(
      jsonEncode(
        List.generate(
          500,
          (i) => {'name': 'Parada $i', 'lat': -17.39 + i / 1e3, 'lon': -66.15},
        ),
      ),
    );
    handler = createWebAppHandler(root);
  });

  tearDownAll(() => webDir.delete(recursive: true));

  group('gzip', () {
    test('GET with Accept-Encoding: gzip gets a smaller gzip body', () async {
      final response = await handler(
        request(
          '/main.dart.js',
          headers: {'accept-encoding': 'gzip, deflate, br'},
        ),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-encoding'], 'gzip');
      expect(response.headers['vary'], 'Accept-Encoding');
      expect(response.headers['content-type'], 'text/javascript');
      expect(response.headers['etag'], isNotNull);
      expect(response.headers['cache-control'], 'no-cache');
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
      final response = await handler(
        request(
          '/assets/assets/search/search.json',
          headers: {'accept-encoding': 'gzip'},
        ),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'application/json');
      expect(response.headers['content-encoding'], 'gzip');
      final original = await File(
        '${webDir.path}/assets/assets/search/search.json',
      ).readAsBytes();
      final body = await bodyOf(response);
      expect(body.length, lessThan(original.length ~/ 4));
      expect(gzip.decode(body), original);
    });

    test('a 304 revalidation is not re-encoded', () async {
      final first = await handler(
        request('/main.dart.js', headers: {'accept-encoding': 'gzip'}),
      );
      final etag = first.headers['etag']!;
      final response = await handler(
        request(
          '/main.dart.js',
          headers: {'accept-encoding': 'gzip', 'if-none-match': etag},
        ),
      );
      expect(response.statusCode, 304);
      expect(response.headers['content-encoding'], isNull);
      // shelf stamps `content-length: 0` on any body-less response whose
      // headers are changed (corsMiddleware already did that on every 304);
      // what matters here is that it is not the size of a gzip body.
      expect(response.headers['content-length'], anyOf(isNull, '0'));
      expect(response.headers['etag'], etag);
      // A 304 repeats the caching headers of the 200 it stands for.
      expect(response.headers['cache-control'], 'no-cache');
      expect(response.headers['vary'], 'Accept-Encoding');
      expect(await bodyOf(response), isEmpty);
    });

    test('a 304 by If-Modified-Since is not re-encoded either', () async {
      final first = await handler(request('/main.dart.js'));
      final response = await handler(
        request(
          '/main.dart.js',
          headers: {
            'accept-encoding': 'gzip',
            'if-modified-since': first.headers['last-modified']!,
          },
        ),
      );
      expect(response.statusCode, 304);
      expect(response.headers['content-encoding'], isNull);
      expect(response.headers['content-length'], anyOf(isNull, '0'));
    });

    test('range requests are answered with identity bytes', () async {
      final response = await handler(
        request(
          '/main.dart.js',
          headers: {'accept-encoding': 'gzip', 'range': 'bytes=0-99'},
        ),
      );
      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes 0-99/${mainJs.length}');
      expect(response.headers['content-encoding'], isNull);
      expect(response.headers['content-length'], '100');
      expect(await bodyOf(response), mainJs.sublist(0, 100));
    });

    test('HEAD keeps the identity Content-Length and sends no body', () async {
      final response = await handler(
        request(
          '/main.dart.js',
          method: 'HEAD',
          headers: {'accept-encoding': 'gzip'},
        ),
      );
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

      Response already(Request _) =>
          Response.ok('x' * 2048, headers: {'vary': 'accept-encoding'});
      final kept = await gzipStatic()(already)(request('/x'));
      expect(kept.headers['vary'], 'accept-encoding');
    });
  });

  group('Cache-Control', () {
    test('only content-hashed names are immutable', () {
      const cases = {
        '': mutableCacheControl,
        'index.html': mutableCacheControl,
        'flutter_bootstrap.js': mutableCacheControl,
        'flutter_service_worker.js': mutableCacheControl,
        'main.dart.js': mutableCacheControl,
        'version.json': mutableCacheControl,
        'icons/Icon-192.png': mutableCacheControl,
        'canvaskit/canvaskit.wasm': mutableCacheControl,
        'assets/assets/search/search.json': mutableCacheControl,
        'assets/fonts/MaterialIcons-Regular.otf': mutableCacheControl,
        // --web-content-hash output (Flutter 3.50+)
        'main.dart.1a2b3c4d.js': immutableCacheControl,
        'main.dart.f215ce97.wasm': immutableCacheControl,
        'main.dart.1a2b3c4d.js.map': immutableCacheControl,
        'assets/AssetManifest.bin.1a2b3c4d.json': immutableCacheControl,
        'assets/FontManifest.1a2b3c4d.json': immutableCacheControl,
        'assets/NOTICES.1a2b3c4d': immutableCacheControl,
        'assets/app-0123456789abcdef.css': immutableCacheControl,
      };
      for (final entry in cases.entries) {
        expect(cacheControlFor(entry.key), entry.value, reason: entry.key);
      }
    });

    test(
      'a 404 for a hashed-looking name is no-cache, not immutable',
      () async {
        final response = await handler(
          Request('GET', Uri.parse('http://x/assets/foo-0123456789ab.png')),
        );
        expect(response.statusCode, 404);
        expect(response.headers['cache-control'], 'no-cache');
      },
    );

    test(
      'the SPA fallback for a hashed-looking deep link is no-cache',
      () async {
        final response = await handler(
          Request('GET', Uri.parse('http://x/stops/stop-13760954848')),
        );
        expect(response.statusCode, 200);
        expect(response.headers['cache-control'], 'no-cache');
      },
    );

    test('a run of digits alone (date stamp) is not a content hash', () {
      expect(cacheControlFor('logo-20261027.png'), mutableCacheControl);
      expect(cacheControlFor('gtfs-20260916.zip'), mutableCacheControl);
      expect(
        cacheControlFor('main.dart.1a2b3c4d.js', statusCode: 404),
        mutableCacheControl,
      );
    });

    test('index.html and / are no-cache', () async {
      for (final path in ['/', '/index.html']) {
        final response = await handler(request(path));
        expect(response.statusCode, 200, reason: path);
        expect(response.headers['cache-control'], 'no-cache', reason: path);
        expect(response.headers['etag'], isNotNull, reason: path);
      }
    });

    test('a hashed file is immutable (and still gzipped)', () async {
      final response = await handler(
        request('/main.dart.1a2b3c4d.js', headers: {'accept-encoding': 'gzip'}),
      );
      expect(response.statusCode, 200);
      expect(response.headers['cache-control'], immutableCacheControl);
      expect(response.headers['content-encoding'], 'gzip');
    });

    test('the SPA fallback serves index.html as no-cache, gzipped', () async {
      final response = await handler(
        request('/routes', headers: {'accept-encoding': 'gzip'}),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'text/html');
      expect(response.headers['cache-control'], 'no-cache');
      expect(response.headers['content-encoding'], 'gzip');
      expect(gzip.decode(await bodyOf(response)), indexHtml);
    });

    test('a missing asset is a genuine 404, no-cache', () async {
      final response = await handler(request('/assets/missing.json'));
      expect(response.statusCode, 404);
      expect(response.headers['cache-control'], 'no-cache');
    });

    test('an explicit Cache-Control is left alone', () async {
      Response stub(Request _) =>
          Response.ok('x', headers: {'cache-control': 'max-age=5'});
      final response = await staticCacheControl()(stub)(request('/x'));
      expect(response.headers['cache-control'], 'max-age=5');
    });
  });

  group('precompressed sidecars', () {
    late List<int> bootstrapJs;
    late List<int> sidecarBytes;

    setUpAll(() async {
      final root = webDir.path;
      bootstrapJs = utf8.encode(
        List.generate(100, (i) => 'window.boot$i = function(){};\n').join(),
      );
      await File('$root/flutter_bootstrap.js').writeAsBytes(bootstrapJs);
      // Deliberately NOT gzip(bootstrapJs): the only way to tell "served the
      // sidecar" from "gzipped the file on the fly" is a body that decodes
      // to something else.
      sidecarBytes = gzip.encode(
        utf8.encode('/* served from flutter_bootstrap.js.gz */'),
      );
      await File('$root/flutter_bootstrap.js.gz').writeAsBytes(sidecarBytes);
    });

    test(
      'a fresh sidecar is served as-is, with its own length and ETag',
      () async {
        final response = await handler(
          request(
            '/flutter_bootstrap.js',
            headers: {'accept-encoding': 'gzip'},
          ),
        );
        expect(response.statusCode, 200);
        expect(response.headers['content-encoding'], 'gzip');
        expect(response.headers['content-length'], '${sidecarBytes.length}');
        expect(response.headers['content-type'], contains('javascript'));
        expect(response.headers['etag'], startsWith('"gz-'));
        expect(response.headers['last-modified'], isNotNull);
        expect(response.headers['vary'], 'Accept-Encoding');
        expect(response.headers['cache-control'], 'no-cache');
        expect(response.headers['accept-ranges'], isNull);
        expect(await bodyOf(response), sidecarBytes);
      },
    );

    test('without Accept-Encoding the file itself is served', () async {
      final response = await handler(request('/flutter_bootstrap.js'));
      expect(response.statusCode, 200);
      expect(response.headers['content-encoding'], isNull);
      expect(response.headers['content-length'], '${bootstrapJs.length}');
      expect(await bodyOf(response), bootstrapJs);
    });

    test('a sidecar older than its file is ignored: gzip on the fly', () async {
      final root = webDir.path;
      final original = File('$root/version.json');
      final stale = File('$root/version.json.gz');
      await stale.writeAsBytes(gzip.encode(utf8.encode('{"stale":true}')));
      await stale.setLastModified(
        (await original.lastModified()).subtract(const Duration(hours: 1)),
      );
      addTearDown(() => stale.delete());

      final response = await handler(
        request('/version.json', headers: {'accept-encoding': 'gzip'}),
      );
      expect(response.statusCode, 200);
      expect(response.headers['etag'], isNot(startsWith('"gz-')));
      final body = await bodyOf(response);
      // version.json is under 512 bytes: on the fly it stays identity,
      // which is exactly the point — the stale gzip never reached the wire.
      expect(response.headers['content-encoding'], isNull);
      expect(body, await original.readAsBytes());
    });

    test('HEAD and Range requests never use the sidecar', () async {
      final head = await handler(
        request(
          '/flutter_bootstrap.js',
          method: 'HEAD',
          headers: {'accept-encoding': 'gzip'},
        ),
      );
      expect(head.statusCode, 200);
      expect(head.headers['content-encoding'], isNull);
      expect(head.headers['content-length'], '${bootstrapJs.length}');
      expect(await bodyOf(head), isEmpty);

      final range = await handler(
        request(
          '/flutter_bootstrap.js',
          headers: {'accept-encoding': 'gzip', 'range': 'bytes=0-9'},
        ),
      );
      expect(range.statusCode, 206);
      expect(range.headers['content-encoding'], isNull);
      expect(await bodyOf(range), bootstrapJs.sublist(0, 10));
    });

    test('If-None-Match with the sidecar ETag is a bare 304', () async {
      final first = await handler(
        request('/flutter_bootstrap.js', headers: {'accept-encoding': 'gzip'}),
      );
      final etag = first.headers['etag']!;
      final response = await handler(
        request(
          '/flutter_bootstrap.js',
          headers: {'accept-encoding': 'gzip', 'if-none-match': etag},
        ),
      );
      expect(response.statusCode, 304);
      expect(response.headers['etag'], etag);
      expect(response.headers['content-encoding'], isNull);
      expect(response.headers['content-length'], anyOf(isNull, '0'));
      expect(response.headers['cache-control'], 'no-cache');
      expect(response.headers['vary'], 'Accept-Encoding');
      expect(await bodyOf(response), isEmpty);
    });

    test('If-Modified-Since at the file date is a 304 too', () async {
      final first = await handler(
        request('/flutter_bootstrap.js', headers: {'accept-encoding': 'gzip'}),
      );
      final response = await handler(
        request(
          '/flutter_bootstrap.js',
          headers: {
            'accept-encoding': 'gzip',
            'if-modified-since': first.headers['last-modified']!,
          },
        ),
      );
      expect(response.statusCode, 304);
      expect(await bodyOf(response), isEmpty);
    });

    test('the identity ETag and the sidecar ETag differ (Vary keeps them '
        'apart; a cache never answers one with the other)', () async {
      final identity = await handler(request('/flutter_bootstrap.js'));
      final compressed = await handler(
        request('/flutter_bootstrap.js', headers: {'accept-encoding': 'gzip'}),
      );
      expect(identity.headers['etag'], isNot(compressed.headers['etag']));
      final cross = await handler(
        request(
          '/flutter_bootstrap.js',
          headers: {
            'accept-encoding': 'gzip',
            'if-none-match': identity.headers['etag']!,
          },
        ),
      );
      expect(cross.statusCode, 200, reason: 'the identity tag is not ours');
      expect(await bodyOf(cross), sidecarBytes);
    });

    test('a directory request uses index.html\'s sidecar', () async {
      final root = webDir.path;
      final sidecar = File('$root/index.html.gz');
      final marker = gzip.encode(utf8.encode('<!-- index.html.gz -->'));
      await sidecar.writeAsBytes(marker);
      addTearDown(() => sidecar.delete());

      final response = await handler(
        request('/', headers: {'accept-encoding': 'gzip'}),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'text/html');
      expect(response.headers['cache-control'], 'no-cache');
      expect(await bodyOf(response), marker);
    });

    test('the SPA fallback never picks a sidecar (deep links stay on the '
        'fly)', () async {
      final response = await handler(
        request('/stops/123', headers: {'accept-encoding': 'gzip'}),
      );
      expect(response.statusCode, 200);
      expect(response.headers['etag'], isNot(startsWith('"gz-')));
      expect(gzip.decode(await bodyOf(response)), indexHtml);
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

    test(
      'the wire carries gzip bytes with a matching Content-Length',
      () async {
        final (res, bytes) = await fetch(
          '/main.dart.js',
          acceptEncoding: 'gzip',
        );
        expect(res.statusCode, 200);
        expect(res.headers.value('content-encoding'), 'gzip');
        expect(res.headers.value('vary'), 'Accept-Encoding');
        expect(res.headers.value('cache-control'), 'no-cache');
        expect(res.headers.contentLength, bytes.length);
        expect(bytes.length, lessThan(mainJs.length ~/ 5));
        expect(gzip.decode(bytes), mainJs);
      },
    );

    test('the wire carries identity bytes without Accept-Encoding', () async {
      final (res, bytes) = await fetch('/main.dart.js');
      expect(res.statusCode, 200);
      expect(res.headers.value('content-encoding'), isNull);
      expect(res.headers.contentLength, mainJs.length);
      expect(bytes, mainJs);
    });

    test(
      'a transparent client (dart:io default) sees the original bytes',
      () async {
        // HttpClient sends Accept-Encoding: gzip and decompresses by itself.
        final (res, bytes) = await fetch('/main.dart.js', autoUncompress: true);
        expect(res.statusCode, 200);
        expect(bytes, mainJs);
      },
    );

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
