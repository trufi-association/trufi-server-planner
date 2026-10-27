import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

/// The handler for the Flutter web build in [directory]: static files with
/// `index.html` as the SPA fallback.
///
/// `bin/server.dart` and the tests build the handler through this function
/// so what is tested is what runs.
Handler createWebAppHandler(String directory) {
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

  return spaFallback;
}
