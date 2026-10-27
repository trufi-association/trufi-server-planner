import 'dart:io';

import 'package:path/path.dart' as p;

/// File extensions worth a `.gz` sidecar: text and wasm that the browser
/// decodes itself. Already-compressed formats (png, woff2, zip, …) are left
/// alone, as `shelf_gzip` leaves them alone on the fly.
const precompressibleExtensions = {
  'js',
  'mjs',
  'wasm',
  'json',
  'html',
  'css',
  'map',
  'txt',
  'svg',
  'xml',
  'webmanifest',
  'ttf',
  'otf',
};

/// Below this size the gzip framing eats the gain; it is also `shelf_gzip`'s
/// threshold on the fly, so the two paths agree on what gets compressed.
const precompressMinBytes = 512;

/// What one [precompressDirectory] pass did.
class PrecompressSummary {
  /// Sidecars written (new or replaced because the file changed).
  int written = 0;

  /// Sidecars left alone: already as new as their file.
  int fresh = 0;

  /// Files without a sidecar: too small, or gzip would not shrink them.
  int skipped = 0;

  /// Sidecars deleted: their file is no longer worth one (shrank, or gzip
  /// stopped shrinking it). A `.gz` without a sibling is left alone: the
  /// handler never serves it, and it may be a build's own asset.
  int removed = 0;

  /// Files the pass could not handle (unreadable, or a directory that
  /// refuses the write, e.g. `web/` mounted read-only): logged, not thrown.
  int failed = 0;

  /// Size of the files that got a sidecar in this pass, and of the sidecars.
  int bytesBefore = 0;
  int bytesAfter = 0;

  @override
  String toString() {
    final ratio = bytesBefore == 0
        ? ''
        : ' (${(100 * (1 - bytesAfter / bytesBefore)).toStringAsFixed(0)}%'
              ' smaller: $bytesBefore → $bytesAfter bytes)';
    final failures = failed == 0 ? '' : ', $failed failed';
    return 'precompress: $written written$ratio, $fresh fresh, '
        '$skipped skipped, $removed removed$failures';
  }
}

/// Writes a gzip sidecar `<file>.gz` next to every file under [directory]
/// whose extension is in [extensions] and which is at least [minBytes] long,
/// at zlib [level] (9: paid once, served many times). A sidecar carries its
/// file's modification time: one whose time matches (to the second) is kept,
/// any other (the file was redeployed over it, newer or, with `tar`/`rsync
/// -a`/`cp -p` preserving dates, older) is rewritten; one that gzip would no
/// longer shrink is deleted. A `.gz` without a sibling is left alone. Each
/// sidecar is written to a temporary name and renamed into place, so a server
/// serving the directory never sees a half-written one. A missing directory
/// is an empty pass, and a file or directory that cannot be read or written
/// is counted in [PrecompressSummary.failed] and logged, never thrown.
///
/// Idempotent: run it at every start of the server, or after copying a new
/// build into place (`dart run bin/precompress.dart web`).
Future<PrecompressSummary> precompressDirectory(
  String directory, {
  Set<String> extensions = precompressibleExtensions,
  int level = 9,
  int minBytes = precompressMinBytes,
}) async {
  final summary = PrecompressSummary();
  final root = Directory(directory);
  if (!await root.exists()) return summary;
  final codec = GZipCodec(level: level);
  // Snapshot first: the pass creates and deletes entries while it runs.
  final entries = await root
      .list(recursive: true, followLinks: false)
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
  for (final file in entries) {
    try {
      await _precompressFile(file, summary, codec, extensions, minBytes);
    } on FileSystemException catch (e) {
      summary.failed++;
      stderr.writeln(
        'precompress: ${file.path}: ${e.message}'
        '${e.osError == null ? '' : ' (${e.osError})'}',
      );
    }
  }
  return summary;
}

Future<void> _precompressFile(
  File file,
  PrecompressSummary summary,
  GZipCodec codec,
  Set<String> extensions,
  int minBytes,
) async {
  final path = file.path;
  if (path.endsWith('.gz.tmp')) {
    // Leftover of an interrupted pass.
    await _deleteIfExists(file);
    return;
  }
  if (path.endsWith('.gz')) return;
  final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
  if (!extensions.contains(extension)) return;
  final stat = await file.stat();
  final sidecar = File('$path.gz');
  final sidecarStat = await sidecar.stat();
  final hasSidecar = sidecarStat.type == FileSystemEntityType.file;
  if (stat.size < minBytes) {
    if (hasSidecar) {
      await _deleteIfExists(sidecar);
      summary.removed++;
    }
    summary.skipped++;
    return;
  }
  if (hasSidecar && sameSecond(sidecarStat.modified, stat.modified)) {
    summary.fresh++;
    return;
  }
  final bytes = codec.encode(await file.readAsBytes());
  if (bytes.length >= stat.size) {
    if (hasSidecar) {
      await _deleteIfExists(sidecar);
      summary.removed++;
    }
    summary.skipped++;
    return;
  }
  final tmp = File('$path.gz.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(sidecar.path);
  // The sidecar carries its file's date: that is what says "this gzip is
  // of this file", whatever order a redeploy gives the two mtimes.
  await sidecar.setLastModified(stat.modified);
  summary.written++;
  summary.bytesBefore += stat.size;
  summary.bytesAfter += bytes.length;
}

/// Whether two modification times are the same at second resolution, the
/// precision `File.setLastModified` and most filesystems guarantee.
bool sameSecond(DateTime a, DateTime b) =>
    a.millisecondsSinceEpoch ~/ 1000 == b.millisecondsSinceEpoch ~/ 1000;

Future<void> _deleteIfExists(File file) async {
  try {
    await file.delete();
  } on PathNotFoundException {
    // Already gone.
  }
}
