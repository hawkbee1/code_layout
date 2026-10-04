// Developer CLI: lays out a code graph written by the engine CLI
// (`dart run code_analysis_engine:analyze <folder> --out graph.json`) and
// writes a code map file: `.dc3d` (gzipped .fscene) or plain `.fscene`.
//
//   dart run code_layout:layout graph.json --out map.dc3d

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:code_graph/code_graph.dart';
import 'package:code_layout/code_layout.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('out', help: 'Output: map.dc3d (gzipped) or map.fscene.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n${parser.usage}');
    exit(1);
  }
  final out = options.option('out');
  if (options.flag('help') || options.rest.length != 1 || out == null) {
    stdout.writeln(
      'Usage: dart run code_layout:layout <graph.json> --out <map.dc3d>\n'
      '${parser.usage}',
    );
    exit(options.flag('help') ? 0 : 64);
  }

  final graph = CodeGraph.fromJson(
    jsonDecode(File(options.rest.single).readAsStringSync())
        as Map<String, Object?>,
  );
  final watch = Stopwatch()..start();
  final map = const CodeLayoutEngine().layout(graph);
  final layoutMs = watch.elapsedMilliseconds;
  const codec = CodeMapCodec();
  final bytes = out.endsWith('.fscene')
      ? utf8.encode(codec.encodeToJson(map))
      : codec.encodeToBytes(map);
  File(out).writeAsBytesSync(bytes);
  stdout.writeln(
    'Laid out ${graph.nodes.length} nodes in $layoutMs ms; wrote $out '
    '(${(bytes.length / 1e6).toStringAsFixed(1)} MB) in '
    '${watch.elapsedMilliseconds - layoutMs} ms',
  );
}
