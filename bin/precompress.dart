import 'dart:io';

import 'package:trufi_server_planner/precompress.dart';

/// Writes the `.gz` sidecars of a web build: `dart run bin/precompress.dart
/// [directory]` (default `web`). The server runs the same pass at start-up
/// unless `PRECOMPRESS_WEB=0`; this is for a deploy that wants them in place
/// before the restart, or for a build served by something else.
Future<void> main(List<String> args) async {
  final directory = args.isEmpty ? 'web' : args.first;
  if (!await Directory(directory).exists()) {
    stderr.writeln('precompress: no such directory: $directory');
    exit(2);
  }
  print(await precompressDirectory(directory));
}
