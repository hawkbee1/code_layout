import 'package:code_layout/code_layout.dart';
import 'package:test/test.dart';

void main() {
  group(Vec3, () {
    test('does arithmetic in double precision', () {
      const a = Vec3(1, 2, 2);

      expect(a + const Vec3(1, 1, 1), const Vec3(2, 3, 3));
      expect(a - a, Vec3.zero);
      expect(a * 2, const Vec3(2, 4, 4));
      expect(a.length, 3);
      expect(a.length2, 9);
      expect(a.withLength(6), const Vec3(2, 4, 4));
      expect(Vec3.zero.withLength(2), const Vec3(2, 0, 0));
      expect(a.hashCode, const Vec3(1, 2, 2).hashCode);
      expect(a.toString(), 'Vec3(1.0, 2.0, 2.0)');
    });
  });

  group('fibonacciDirection', () {
    test('gives unit vectors, and +x for a single point', () {
      expect(fibonacciDirection(0, 1), const Vec3(1, 0, 0));
      for (var i = 0; i < 10; i++) {
        expect(fibonacciDirection(i, 10).length, closeTo(1, 1e-12));
      }
    });
  });
}
