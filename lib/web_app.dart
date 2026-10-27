import 'dart:io' show HttpHeaders;

import 'package:shelf/shelf.dart';
import 'package:shelf_gzip/shelf_gzip.dart' as shelf_gzip;
import 'package:shelf_static/shelf_static.dart';

/// `Cache-Control` for files whose name carries no content hash.
///
/// A Flutter web build keeps the same file names across deploys
/// (`main.dart.js`, `assets/**`, `canvaskit/**`) unless it is built with
/// `--web-content-hash` (Flutter 3.50+), and since Flutter 3.41 the generated
/// `flutter_service_worker.js` only unregisters the old offline-first worker,
/// so the browser's HTTP cache is the only cache layer left. Without a
/// `Cache-Control` header browsers cache heuristically (a fraction of the
/// `Last-Modified` age: days, for a build deployed weeks ago), which is how a
/// stale `main.dart.js` outlives a deploy. `no-cache` keeps the bytes cached
/// but revalidates them on every use; shelf_static answers the revalidation
/// with a `304` through `ETag` / `Last-Modified`, so the cost is one header
/// round trip per file. This is also what the Flutter deployment docs
/// prescribe for the unhashed files of a build.
const mutableCacheControl = 'no-cache';

/// `Cache-Control` for files whose name carries a content hash: the URL
/// changes whenever the content does, so browsers may keep them for a year
/// without revalidating.
const immutableCacheControl = 'public, max-age=31536000, immutable';

/// A content hash in a file name, as `flutter build web --web-content-hash`
/// writes it (`main.dart.1a2b3c4d.js`, `AssetManifest.bin.1a2b3c4d.json`,
/// `NOTICES.1a2b3c4d`, `main.dart.1a2b3c4d.js.map`) or the common
/// `app-1a2b3c4d.css` form.
final _hashedFileName = RegExp(r'[.-][0-9a-f]{8,}(\.[A-Za-z0-9]+)*$');

/// The `Cache-Control` value for the static file at [path].
String cacheControlFor(String path) =>
    _hashedFileName.hasMatch(path) ? immutableCacheControl : mutableCacheControl;

/// Adds `Cache-Control` (see [cacheControlFor]) to every response that does
/// not already carry one, 304s and 404s included: a 304 must repeat the
/// caching headers of the 200 it stands for, and an uncontrolled 404 is
/// heuristically cacheable too.
Middleware staticCacheControl() => (inner) => (request) async {
      final response = await inner(request);
      if (response.headers.containsKey(HttpHeaders.cacheControlHeader)) {
        return response;
      }
      return response.change(headers: {
        HttpHeaders.cacheControlHeader: cacheControlFor(request.url.path),
      });
    };

/// Whether [request] accepts the `gzip` content coding, honouring `q`
/// values: `gzip;q=0` opts out, `*` opts in unless `gzip` is listed.
bool acceptsGzip(Request request) {
  final header = request.headers[HttpHeaders.acceptEncodingHeader];
  if (header == null) return false;
  bool? wildcard;
  for (final entry in header.split(',')) {
    final parts = entry.split(';');
    final coding = parts.first.trim().toLowerCase();
    var q = 1.0;
    for (final param in parts.skip(1)) {
      final pair = param.split('=');
      if (pair.length == 2 && pair[0].trim().toLowerCase() == 'q') {
        q = double.tryParse(pair[1].trim()) ?? 0;
      }
    }
    if (coding == 'gzip' || coding == 'x-gzip') return q > 0;
    if (coding == '*') wildcard = q > 0;
  }
  return wildcard ?? false;
}

/// Gzip-encodes the body of `200` responses to `GET` requests that accept it,
/// and marks every response with `Vary: Accept-Encoding` so shared caches keep
/// the two representations apart.
///
/// The encoding is `package:shelf_gzip`'s, which also leaves bodies under
/// 512 bytes and already-compressed types (PNG, WOFF2, ZIP, ...) alone. This
/// wrapper adds what shelf_gzip 4.1.0 leaves to the caller: it only
/// substring-matches `Accept-Encoding`, sets no `Vary`, and would re-encode
/// a `304` (no body), a `HEAD` response (no body, but the file's
/// `Content-Length`) or a `206` (whose `Content-Range` counts identity bytes).
///
/// [level] is zlib's: 6 shrinks `main.dart.js` 6% more than shelf_gzip's
/// default 4 for twice the CPU (139 ms vs 70 ms for 5 MB on an M-series Mac).
/// The transfer is what the users on slow links pay for, the CPU is paid once
/// per cold load on a server that otherwise idles, so 6 it is.
Middleware gzipStatic({int level = 6}) => (inner) => (request) async {
      final response = _varyOnAcceptEncoding(await inner(request));
      if (request.method != 'GET' ||
          response.statusCode != 200 ||
          response.headers.containsKey(HttpHeaders.contentRangeHeader) ||
          !acceptsGzip(request)) {
        return response;
      }
      final encoded = await shelf_gzip.gzipEncodeResponse(
        response,
        compressionLevel: level,
        addCompressionRatioHeader: false,
      );
      if (identical(encoded, response)) return response;
      // A byte range of the gzip body is not a byte range of the file:
      // stop advertising ranges on the compressed representation.
      return encoded.change(headers: {HttpHeaders.acceptRangesHeader: null});
    };

Response _varyOnAcceptEncoding(Response response) {
  final vary = response.headers[HttpHeaders.varyHeader];
  if (vary != null &&
      vary.toLowerCase().split(',').map((e) => e.trim()).contains('accept-encoding')) {
    return response;
  }
  return response.change(headers: {
    HttpHeaders.varyHeader:
        vary == null ? 'Accept-Encoding' : '$vary, Accept-Encoding',
  });
}

/// The handler for the Flutter web build in [directory]: static files with
/// `index.html` as the SPA fallback, `Cache-Control` and gzip.
///
/// `bin/server.dart` and the tests build the pipeline through this function
/// so what is tested is what runs.
Handler createWebAppHandler(String directory, {int gzipLevel = 6}) {
  final files = createStaticHandler(directory, defaultDocument: 'index.html');

  // SPA fallback: when a path without a file extension 404s, serve
  // index.html so the Flutter client-side router can resolve deep
  // links (e.g. /routes, /stops/123) on hard reload.
  Future<Response> spaFallback(Request req) async {
    final res = await files(req);
    if (res.statusCode != 404 || req.url.path.contains('.')) return res;
    return files(Request(
      'GET',
      req.requestedUri.replace(path: '/'),
      headers: req.headers,
      context: req.context,
    ));
  }

  return const Pipeline()
      .addMiddleware(staticCacheControl())
      .addMiddleware(gzipStatic(level: gzipLevel))
      .addHandler(spaFallback);
}
