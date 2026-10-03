import 'dart:math' as math;

import 'package:code_layout/code_layout.dart';
import 'package:test/test.dart';

Vec3 _bruteForce(int i, List<Vec3> positions, List<double> masses) {
  var force = Vec3.zero;
  for (var j = 0; j < positions.length; j++) {
    if (j == i) continue;
    final d = positions[i] - positions[j];
    final d2 = d.length2 + 1e-3;
    force = force + d * (masses[i] * masses[j] / (d2 * math.sqrt(d2)));
  }
  return force;
}

void main() {
  group(Octree, () {
    test('matches the exact sum when it never approximates', () {
      final random = math.Random(1);
      final positions = [
        for (var i = 0; i < 200; i++)
          Vec3(random.nextDouble(), random.nextDouble(), random.nextDouble()) *
              50,
      ];
      final masses = [for (var i = 0; i < 200; i++) 1 + random.nextDouble()];
      final tree = Octree.build(positions, masses);

      for (final i in [0, 57, 199]) {
        final exact = _bruteForce(i, positions, masses);
        expect(
          (tree.repulsionOn(i, theta: 0) - exact).length,
          lessThan(1e-9 * exact.length + 1e-12),
        );
      }
    });

    test('stays close to the exact sum with the default angle', () {
      final random = math.Random(2);
      final positions = [
        for (var i = 0; i < 2000; i++)
          Vec3(random.nextDouble(), random.nextDouble(), random.nextDouble()) *
              100,
      ];
      final masses = List<double>.filled(2000, 1);
      final tree = Octree.build(positions, masses);

      for (final i in [3, 999, 1500]) {
        final exact = _bruteForce(i, positions, masses);
        final approximate = tree.repulsionOn(i);
        expect((approximate - exact).length / exact.length, lessThan(0.1));
      }
    });

    test('handles bodies at the same position and an empty tree', () {
      final tree = Octree.build(
        List.filled(50, Vec3.zero),
        List<double>.filled(50, 1),
      );

      expect(tree.repulsionOn(0), Vec3.zero);
      expect(Octree.build(const [], const []), isA<Octree>());
    });
  });
}
