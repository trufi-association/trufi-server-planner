import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:trufi_server_planner/web_app.dart';

/// Unit tests of the web-app pipeline (`createWebAppHandler`): the real
/// shelf_static handler over a temporary `web/` fixture, no network, so they
/// run in `dart test` without the server.
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

  group('static files', () {
    test('index.html and / are served', () async {
      for (final path in ['/', '/index.html']) {
        final response = await handler(request(path));
        expect(response.statusCode, 200, reason: path);
        expect(response.headers['content-type'], 'text/html', reason: path);
        expect(await bodyOf(response), indexHtml, reason: path);
      }
    });

    test('the SPA fallback serves index.html for extension-less paths',
        () async {
      final response = await handler(request('/routes'));
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'text/html');
      expect(await bodyOf(response), indexHtml);
    });

    test('a missing asset is a genuine 404', () async {
      final response = await handler(request('/assets/missing.json'));
      expect(response.statusCode, 404);
    });
  });

  group('conditional requests', () {
    test('If-None-Match with the ETag answers 304', () async {
      final first = await handler(request('/main.dart.js'));
      final etag = first.headers['etag']!;
      final response = await handler(
        request('/main.dart.js', headers: {'if-none-match': etag}),
      );
      expect(response.statusCode, 304);
      expect(response.headers['etag'], etag);
      expect(await bodyOf(response), isEmpty);
    });

    test('If-Modified-Since equal to Last-Modified answers 304', () async {
      // shelf_static 1.1.3 kept the mtime's microseconds in this comparison
      // and answered 200 with the whole file; 1.2.0 truncates to seconds.
      final first = await handler(request('/main.dart.js'));
      final response = await handler(request(
        '/main.dart.js',
        headers: {'if-modified-since': first.headers['last-modified']!},
      ));
      expect(response.statusCode, 304);
      expect(await bodyOf(response), isEmpty);
    });
  });
}
