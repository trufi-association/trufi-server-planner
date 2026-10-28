import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:trufi_server_planner/precompress.dart';

/// `precompressDirectory`: one `.gz` per compressible file, idempotent,
/// refreshes stale sidecars, leaves orphans alone, never leaves a temp file.
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
    expect(summary.removed, 0, reason: 'orphan.js.gz is left alone');
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
        sameSecond(
          await sidecar.lastModified(),
          await File('$root/$name').lastModified(),
        ),
        isTrue,
        reason: 'a sidecar carries its file\'s date',
      );
    }
    expect(File('$root/small.js.gz').existsSync(), isFalse);
    expect(File('$root/random.txt.gz').existsSync(), isFalse);
    expect(File('$root/image.png.gz').existsSync(), isFalse);
    expect(File('$root/orphan.js.gz').existsSync(), isTrue);
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

  test('a file redeployed with an OLDER date than its sidecar is still '
      'recompressed (tar, rsync -a and cp -p preserve dates)', () async {
    await precompressDirectory(root);
    final file = File('$root/big.js');
    final sidecar = File('$root/big.js.gz');
    final redeployed = text(300, 'older-build-newer-content');
    await file.writeAsBytes(redeployed);
    await file.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );

    final summary = await precompressDirectory(root);

    expect(summary.written, 1, reason: 'dates differ, the sidecar is stale');
    expect(gzip.decode(await sidecar.readAsBytes()), redeployed);
    expect(
      sameSecond(await sidecar.lastModified(), await file.lastModified()),
      isTrue,
    );
  });

  test('a compressible file under the threshold gets no sidecar', () async {
    await File('$root/tiny.js').writeAsBytes(text(12, 'var')); // ~400 bytes
    expect(await File('$root/tiny.js').length(), lessThan(precompressMinBytes));

    final summary = await precompressDirectory(root);

    expect(File('$root/tiny.js.gz').existsSync(), isFalse);
    expect(summary.skipped, 3, reason: 'small.js, random.txt, tiny.js');
  });

  test('a directory that refuses the write is reported, not thrown', () async {
    if (Platform.isWindows) return;
    // root ignores file modes (chmod 555 does not stop it): skip as root,
    // whatever USER says (containers often leave it empty).
    final uid = await Process.run('id', ['-u']);
    if ((uid.stdout as String).trim() == '0') return;
    final locked = Directory('$root/locked');
    await locked.create();
    await File('${locked.path}/app.js').writeAsBytes(text(300, 'locked'));
    await Process.run('chmod', ['555', locked.path]);
    addTearDown(() => Process.run('chmod', ['755', locked.path]));

    final summary = await precompressDirectory(root);

    expect(summary.failed, 1);
    expect(summary.written, 3, reason: 'the other files are still handled');
    expect(summary.toString(), endsWith(', 1 failed'));
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
