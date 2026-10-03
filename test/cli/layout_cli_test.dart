// Runs bin/layout.dart as a process (bin/ is outside coverage).
@Tags(['skip_very_good_optimization'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:code_graph/code_graph.dart';
import 'package:test/test.dart';

import '../helpers/graphs.dart';

Future<ProcessResult> _cli(List<String> arguments) =>
    Process.run('dart', ['run', 'bin/layout.dart', ...arguments]);

void main() {
  group('layout CLI', () {
    late Directory dir;
    late String graphPath;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('layout_cli_');
      addTearDown(() => dir.delete(recursive: true));
      graphPath = '${dir.path}/graph.json';
      File(graphPath).writeAsStringSync(
        jsonEncode(graphOf([node('A'), node('A.m', parent: 'A')]).toJson()),
      );
    });

    test('writes a .dc3d and a plain .fscene', () async {
      for (final name in ['map.dc3d', 'map.fscene']) {
        final out = '${dir.path}/$name';
        final result = await _cli([graphPath, '--out', out]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stdout, contains('Laid out 2 nodes'));
        final map = const CodeMapCodec().decodeFromBytes(
          File(out).readAsBytesSync(),
        );
        expect(map.placements.keys, ['A', 'A.m']);
      }
    });

    test('explains its usage', () async {
      final missing = await _cli([graphPath]);
      final bad = await _cli(['--bogus']);
      final help = await _cli(['--help']);

      expect(missing.exitCode, 64);
      expect(bad.exitCode, 1);
      expect(help.exitCode, 0);
      expect(help.stdout, contains('Usage'));
    });
  });
}
