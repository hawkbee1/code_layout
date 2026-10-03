import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A 3D vector of doubles.
///
/// The layout uses its own type instead of `vector_math`, whose `Vector3`
/// stores single-precision floats: not precise enough to check overlaps of
/// thousands of spheres exactly.
@immutable
class Vec3 {
  /// Creates a vector.
  const new(this.x, this.y, this.z);

  /// The origin.
  static const zero = Vec3(0, 0, 0);

  /// Components.
  final double x;

  /// Components.
  final double y;

  /// Components.
  final double z;

  /// Sum.
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);

  /// Difference.
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);

  /// Scaled by [s].
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  /// Squared length.
  double get length2 => x * x + y * y + z * z;

  /// Length.
  double get length => math.sqrt(length2);

  /// This vector with length [l] (or [fallback] scaled to [l] when zero).
  Vec3 withLength(double l, {Vec3 fallback = const Vec3(1, 0, 0)}) {
    final current = length;
    return current == 0 ? fallback * l : this * (l / current);
  }

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Vec3($x, $y, $z)';
}

/// The [i]-th of [n] points spread evenly on the unit sphere (Fibonacci).
Vec3 fibonacciDirection(int i, int n) {
  if (n <= 1) return const Vec3(1, 0, 0);
  const golden = 2.399963229728653; // pi * (3 - sqrt(5))
  final y = 1 - 2 * (i + 0.5) / n;
  final r = math.sqrt(math.max(0, 1 - y * y));
  final theta = golden * i;
  return Vec3(math.cos(theta) * r, y, math.sin(theta) * r);
}
