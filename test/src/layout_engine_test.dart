import 'package:code_graph/code_graph.dart';
import 'package:code_layout/code_layout.dart';
import 'package:test/test.dart';

import '../helpers/graphs.dart';
import '../helpers/invariants.dart';

void main() {
  group(CodeLayoutEngine, () {
    const engine = CodeLayoutEngine();

    test('lays out an empty graph', () {
      expect(engine.layout(graphOf(const [])).placements, isEmpty);
    });

    test('gives leaves a radius growing with their code', () {
      final map = engine.layout(
        graphOf([
          node('tiny', loc: 0),
          node('small', loc: 8),
          node('big', loc: 1000),
          node('huge', loc: 1000000),
        ]),
      );

      expect(map.placements['tiny']!.radius, 0.5);
      expect(map.placements['small']!.radius, 1);
      expect(map.placements['big']!.radius, closeTo(5, 1e-9));
      expect(map.placements['huge']!.radius, 8);
    });

    test('puts children inside their container, without overlaps', () {
      final map = engine.layout(
        graphOf([
          node('A', loc: 30),
          for (var i = 0; i < 12; i++) node('A.m$i', parent: 'A', loc: i * 5),
          node('B', parent: 'A', loc: 40),
          node('B.m', parent: 'B'),
        ]),
      );

      expectValidLayout(map);
      expect(
        map.placements['A']!.radius,
        greaterThan(map.placements['B']!.radius),
      );
    });

    test('pins the entry node at the origin', () {
      final map = engine.layout(
        graphOf([
          node('main', kind: CodeNodeKind.function),
          node('A'),
          node('B'),
          node('A.m', parent: 'A'),
        ], entry: 'A.m'),
      );

      final a = map.placements['A']!;
      expect((a.x, a.y, a.z), (0.0, 0.0, 0.0));
      expectValidLayout(map);
    });

    test('puts external packages outside the project', () {
      final map = engine.layout(
        graphOf(
          [
            node('A'),
            node('B'),
            node('A.m', parent: 'A'),
            for (final p in ['x', 'y', 'z'])
              CodeNode(
                id: 'pkg:$p',
                kind: CodeNodeKind.externalPackage,
                name: p,
              ),
          ],
          links: const [
            CodeLink(fromId: 'A.m', toId: 'pkg:x', kind: LinkKind.call),
            CodeLink(fromId: 'A.m', toId: 'pkg:y', kind: LinkKind.call),
          ],
        ),
      );

      double reach(String id) {
        final p = map.placements[id]!;
        return Vec3(p.x, p.y, p.z).length;
      }

      final project = [
        for (final id in ['A', 'B']) reach(id) + map.placements[id]!.radius,
      ].reduce((a, b) => a > b ? a : b);
      for (final p in ['pkg:x', 'pkg:y', 'pkg:z']) {
        expect(reach(p) - map.placements[p]!.radius, greaterThan(project));
      }
      expect(map.placements['pkg:x']!.radius, 1.6);
      expectValidLayout(map);
    });

    test('spreads packages pulled in the same direction', () {
      final map = engine.layout(
        graphOf(
          [
            node('A'),
            node('A.m', parent: 'A'),
            for (var i = 0; i < 30; i++)
              CodeNode(
                id: 'pkg:p$i',
                kind: CodeNodeKind.externalPackage,
                name: 'p$i',
              ),
          ],
          links: [
            for (var i = 0; i < 30; i++)
              CodeLink(fromId: 'A.m', toId: 'pkg:p$i', kind: LinkKind.call),
          ],
          entry: 'A',
        ),
      );

      expectValidLayout(map);
    });

    test('spreads the top level out when relaxing is not enough', () {
      final map = engine.layout(
        graphOf([for (var i = 0; i < 60; i++) node('C$i', loc: 500)]),
        options: const LayoutOptions(topIterations: 0, overlapIterations: 1),
      );

      expectValidLayout(map);
    });

    test('moves the package shell out until evenly spread packages fit', () {
      final map = engine.layout(
        graphOf([
          node('A', loc: 1),
          for (var i = 0; i < 300; i++)
            CodeNode(
              id: 'pkg:p$i',
              kind: CodeNodeKind.externalPackage,
              name: 'p$i',
            ),
        ]),
      );

      expectValidLayout(map);
    });

    test('reports progress up to 1', () {
      final progress = <double>[];
      engine.layout(graphOf([node('A'), node('B')]), onProgress: progress.add);

      expect(progress.first, 0.3);
      expect(progress.last, 1);
    });

    group('on a generated 20,000-node project', () {
      late CodeGraph graph;
      late CodeMap map;
      late Duration elapsed;

      setUpAll(() {
        graph = generatedGraph();
        final watch = Stopwatch()..start();
        map = engine.layout(graph);
        elapsed = watch.elapsed;
        // Recorded in the session log.
        // ignore: avoid_print
        print(
          'layout of ${graph.nodes.length} nodes: ${elapsed.inMilliseconds} ms',
        );
      });

      test('is valid', () => expectValidLayout(map));

      test('is fast enough', () {
        expect(elapsed, lessThan(const Duration(seconds: 20)));
      });

      test('keeps nodes of the same file closer together', () {
        final distances = meanDistances(map);

        expect(distances.sameFile, lessThan(distances.otherFile));
      });

      test('is deterministic, whatever the order of the nodes', () {
        final again = engine.layout(generatedGraph(shuffled: true));

        expect(again.placements, map.placements);
      });
    });

    test('falls back to a lattice when relaxing cannot fit the children', () {
      final map = engine.layout(
        graphOf([
          node('A', loc: 1),
          for (var i = 0; i < 40; i++) node('A.m$i', parent: 'A', loc: 900),
        ]),
        options: const LayoutOptions(innerIterations: 0, containerMargin: 0.5),
      );

      expectValidLayout(map);
    });
  });
}
