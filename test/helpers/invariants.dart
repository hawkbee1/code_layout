import 'dart:math' as math;

import 'package:code_graph/code_graph.dart';
import 'package:code_layout/code_layout.dart';
import 'package:test/test.dart';

/// Expects no overlapping siblings and every child inside its parent.
void expectValidLayout(CodeMap map) {
  final graph = map.graph;
  for (final parent in [null, ...graph.nodes.keys]) {
    final children = graph.childrenOf(parent);
    final radii = [for (final c in children) map.placements[c.id]!.radius];
    final positions = [
      for (final c in children)
        Vec3(
          map.placements[c.id]!.x,
          map.placements[c.id]!.y,
          map.placements[c.id]!.z,
        ),
    ];
    expect(
      hasNoOverlap(
        radii,
        positions,
        containerRadius: parent == null ? null : map.placements[parent]!.radius,
      ),
      isTrue,
      reason: 'children of ${parent ?? 'the world'}',
    );
  }
}

/// Mean distance between top-level nodes of the same file, and of
/// different files.
({double sameFile, double otherFile}) meanDistances(CodeMap map) {
  final top = [
    for (final n in map.graph.topLevel)
      if (n.location != null) n,
  ];
  var same = 0.0;
  var sameCount = 0;
  var other = 0.0;
  var otherCount = 0;
  for (var i = 0; i < top.length; i++) {
    for (var j = i + 1; j < top.length; j++) {
      final a = map.placements[top[i].id]!;
      final b = map.placements[top[j].id]!;
      final d = math.sqrt(
        math.pow(a.x - b.x, 2) +
            math.pow(a.y - b.y, 2) +
            math.pow(a.z - b.z, 2),
      );
      if (top[i].location!.filePath == top[j].location!.filePath) {
        same += d;
        sameCount++;
      } else {
        other += d;
        otherCount++;
      }
    }
  }
  return (sameFile: same / sameCount, otherFile: other / otherCount);
}
