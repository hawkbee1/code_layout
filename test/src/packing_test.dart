import 'dart:math' as math;

import 'package:code_layout/code_layout.dart';
import 'package:test/test.dart';

void main() {
  group('relaxOverlaps', () {
    test('separates spheres, even at the same position', () {
      final radii = [1.0, 1.0, 2.0];
      final positions = [Vec3.zero, Vec3.zero, const Vec3(0.5, 0, 0)];

      final ok = relaxOverlaps(
        radii,
        positions,
        gap: 0.1,
        iterations: 100,
        random: math.Random(1),
      );

      expect(ok, isTrue);
      expect(hasNoOverlap(radii, positions), isTrue);
    });

    test('keeps a pinned sphere in place and pulls springs together', () {
      final radii = [1.0, 1.0, 1.0];
      final positions = [Vec3.zero, const Vec3(1, 0, 0), const Vec3(30, 0, 0)];

      relaxOverlaps(
        radii,
        positions,
        gap: 0,
        iterations: 50,
        random: math.Random(1),
        pinned: 0,
        springs: const [(a: 1, b: 2, weight: 1)],
        springStrength: 0.5,
      );

      expect(positions[0], Vec3.zero);
      expect(positions[2].x, lessThan(30));
    });

    test('moves only the other sphere when the first one is pinned', () {
      final radii = [1.0, 1.0];
      final positions = [Vec3.zero, const Vec3(0.5, 0, 0)];

      relaxOverlaps(
        radii,
        positions,
        gap: 0,
        iterations: 5,
        random: math.Random(1),
        pinned: 0,
      );

      expect(positions[0], Vec3.zero);
      expect(hasNoOverlap(radii, positions), isTrue);
    });

    test('pins the second sphere of a pair too', () {
      final radii = [1.0, 1.0];
      final positions = [const Vec3(0.5, 0, 0), Vec3.zero];

      relaxOverlaps(
        radii,
        positions,
        gap: 0,
        iterations: 5,
        random: math.Random(1),
        pinned: 1,
      );

      expect(positions[1], Vec3.zero);
      expect(hasNoOverlap(radii, positions), isTrue);
    });

    test(
      'keeps spheres inside a container and reports when they cannot fit',
      () {
        final radii = List<double>.filled(30, 1);
        final positions = List.filled(30, Vec3.zero);

        final ok = relaxOverlaps(
          radii,
          positions,
          gap: 0,
          iterations: 50,
          random: math.Random(1),
          containerRadius: 2,
        );

        expect(ok, isFalse);
        for (final p in positions) {
          expect(p.length, lessThanOrEqualTo(1 + 1e-9));
        }
      },
    );

    test('does nothing for no spheres', () {
      expect(
        relaxOverlaps(
          const [],
          [],
          gap: 0,
          iterations: 1,
          random: math.Random(1),
        ),
        isTrue,
      );
    });
  });

  group('hasNoOverlap', () {
    test('detects overlaps and spheres outside the container', () {
      expect(hasNoOverlap([1, 1], [Vec3.zero, const Vec3(1, 0, 0)]), isFalse);
      expect(
        hasNoOverlap([1], [const Vec3(2, 0, 0)], containerRadius: 2.5),
        isFalse,
      );
      expect(hasNoOverlap([1], [Vec3.zero]), isTrue);
    });
  });

  group('latticePacking', () {
    test('never overlaps and gives the containing radius', () {
      final radii = [for (var i = 0; i < 20; i++) 0.5 + i * 0.1];

      final packed = latticePacking(radii, gap: 0.2);

      expect(hasNoOverlap(radii, packed.positions), isTrue);
      expect(
        hasNoOverlap(radii, packed.positions, containerRadius: packed.radius),
        isTrue,
      );
    });
  });
}
