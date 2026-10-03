import 'dart:math' as math;

import 'package:code_graph/code_graph.dart';

ProjectInfo _project({String? entry}) => ProjectInfo(
  generator: 'test',
  source: const LocalFolderDescriptor(name: 'test'),
  createdAt: DateTime.utc(2026),
  entryNodeId: entry,
);

/// A graph from [nodes] (in the given order) and [links].
CodeGraph graphOf(
  List<CodeNode> nodes, {
  List<CodeLink> links = const [],
  String? entry,
}) => CodeGraph(
  project: _project(entry: entry),
  nodes: {for (final n in nodes) n.id: n},
  links: links,
);

/// A class (or method when [parent] is set) declared in [file].
CodeNode node(
  String id, {
  String file = 'lib/a.dart',
  String? parent,
  int loc = 10,
  CodeNodeKind? kind,
}) => CodeNode(
  id: id,
  kind: kind ?? (parent == null ? CodeNodeKind.classDecl : CodeNodeKind.method),
  name: id,
  parentId: parent,
  location: SourceLocation(filePath: file, startLine: 1, endLine: 2),
  loc: loc,
  packageName: 'app',
);

/// A generated project: [classes] classes in files of 5, in folders of 10
/// files, each with [methodsPerClass] methods, every 4th class nested in the
/// previous one, a ghost parent, external packages, and [links] calls.
CodeGraph generatedGraph({
  int classes = 2000,
  int methodsPerClass = 9,
  int links = 30000,
  bool shuffled = false,
}) {
  final random = math.Random(42);
  final nodes = <CodeNode>[
    const CodeNode(
      id: 'ghost:flutter:StatelessWidget',
      kind: CodeNodeKind.ghostParent,
      name: 'StatelessWidget',
      packageName: 'flutter',
    ),
    for (final p in ['flutter', 'http', 'bloc'])
      CodeNode(
        id: 'pkg:$p',
        kind: CodeNodeKind.externalPackage,
        name: p,
        packageName: p,
      ),
  ];
  final methods = <String>[];
  String? previous;
  for (var c = 0; c < classes; c++) {
    final file = 'lib/d${c ~/ 50}/f${c ~/ 5}.dart';
    final id = '$file#C$c';
    final parent = c % 4 == 3
        ? previous
        : c % 10 == 0
        ? 'ghost:flutter:StatelessWidget'
        : null;
    nodes.add(
      node(id, file: file, parent: parent, loc: 5 + random.nextInt(200)),
    );
    for (var m = 0; m < methodsPerClass; m++) {
      final methodId = '$id.m$m';
      nodes.add(
        node(methodId, file: file, parent: id, loc: 1 + random.nextInt(30)),
      );
      methods.add(methodId);
    }
    previous = id;
  }
  final callLinks = [
    for (var i = 0; i < links; i++)
      CodeLink(
        fromId: methods[random.nextInt(methods.length)],
        toId: i % 50 == 0
            ? 'pkg:http'
            : methods[random.nextInt(methods.length)],
        kind: LinkKind.call,
        count: 1 + random.nextInt(3),
      ),
  ].where((l) => l.fromId != l.toId).toList();
  if (shuffled) nodes.shuffle(math.Random(7));
  return graphOf(
    nodes,
    links: callLinks,
    entry: nodes.firstWhere((n) => n.id.endsWith('#C1')).id,
  );
}
