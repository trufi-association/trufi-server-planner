import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:trufi_server_planner/precompress.dart';

/// `precompressDirectory`: one `.gz` per compressible file, idempotent,
/// refreshes stale sidecars, drops orphans, never leaves a temp file.
void main() {
  late Directory dir;
  late String root;

  List<int> text(int lines, String seed) =>
      utf8.encode(List.generate(lines, (i) => '$seed line $i;\n').join());

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('trufi-precompress-');
    root = dir.path;
    await File('$root/big.js').writeAsBytes(text(300, 'function'));
    await File('$root/small.js').writeAsString('window.x=1;');
    await File('$root/data.json').writeAsBytes(text(100, '{"k":'));
    await Directory('$root/nested/deep').create(recursive: true);
    await File('$root/nested/deep/app.css').writeAsBytes(text(100, '.a'));
    final random = Random(7);
    await File(
      '$root/random.txt',
    ).writeAsBytes(List.generate(4096, (_) => random.nextInt(256)));
    await File(
      '$root/image.png',
    ).writeAsBytes(List.generate(4096, (i) => (i * 7919 + 13) & 0xff));
    await File('$root/orphan.js.gz').writeAsBytes(gzip.encode([1, 2, 3]));
    await File('$root/big.js.gz.tmp').writeAsString('interrupted');
  });

  tearDown(() => dir.delete(recursive: true));

  test('writes one sidecar per compressible file, nothing else', () async {
    final summary = await precompressDirectory(root);

    expect(summary.written, 3, reason: 'big.js, data.json, app.css');
    expect(summary.skipped, 2, reason: 'small.js, random.txt');
    expect(summary.removed, 1, reason: 'orphan.js.gz');
    expect(summary.fresh, 0);
    expect(summary.bytesAfter, lessThan(summary.bytesBefore ~/ 4));

    for (final name in ['big.js', 'data.json', 'nested/deep/app.css']) {
      final sidecar = File('$root/$name.gz');
      expect(sidecar.existsSync(), isTrue, reason: name);
      expect(
        gzip.decode(await sidecar.readAsBytes()),
        await File('$root/$name').readAsBytes(),
        reason: '$name.gz decodes to the file',
      );
      expect(
        (await sidecar.lastModified()).isBefore(
          await File('$root/$name').lastModified(),
        ),
        isFalse,
        reason: 'a fresh sidecar is never older than its file',
      );
    }
    expect(File('$root/small.js.gz').existsSync(), isFalse);
    expect(File('$root/random.txt.gz').existsSync(), isFalse);
    expect(File('$root/image.png.gz').existsSync(), isFalse);
    expect(File('$root/orphan.js.gz').existsSync(), isFalse);
    expect(File('$root/big.js.gz.tmp').existsSync(), isFalse);
    expect(
      dir
          .listSync(recursive: true)
          .where((e) => e.path.endsWith('.tmp'))
          .toList(),
      isEmpty,
    );
  });

  test('a second pass leaves fresh sidecars alone', () async {
    await precompressDirectory(root);
    final before = await File('$root/big.js.gz').lastModified();

    final again = await precompressDirectory(root);

    expect(again.written, 0);
    expect(again.fresh, 3);
    expect(again.removed, 0);
    expect(await File('$root/big.js.gz').lastModified(), before);
  });

  test('a file newer than its sidecar gets a new one', () async {
    await precompressDirectory(root);
    final sidecar = File('$root/big.js.gz');
    final fresh = text(300, 'redeployed');
    await File('$root/big.js').writeAsBytes(fresh);
    await sidecar.setLastModified(
      DateTime.now().subtract(const Duration(days: 1)),
    );

    final summary = await precompressDirectory(root);

    expect(summary.written, 1);
    expect(summary.fresh, 2);
    expect(gzip.decode(await sidecar.readAsBytes()), fresh);
  });

  test('a sidecar whose file shrank below the threshold is removed', () async {
    await precompressDirectory(root);
    await File('$root/data.json').writeAsString('{}');
    await File(
      '$root/data.json.gz',
    ).setLastModified(DateTime.now().subtract(const Duration(days: 1)));

    final summary = await precompressDirectory(root);

    expect(File('$root/data.json.gz').existsSync(), isFalse);
    expect(summary.removed, 1);
  });

  test('a missing directory is an empty pass', () async {
    final summary = await precompressDirectory('$root/nope');
    expect(summary.written + summary.fresh + summary.skipped, 0);
    expect(
      summary.toString(),
      'precompress: 0 written, 0 fresh, 0 skipped, 0 removed',
    );
  });

  test('the summary reports the saving', () async {
    final summary = await precompressDirectory(root);
    expect(summary.toString(), startsWith('precompress: 3 written ('));
    expect(summary.toString(), contains('% smaller'));
  });
}
