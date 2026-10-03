import 'dart:math' as math;

import 'package:code_layout/src/vec3.dart';

/// A spring between two spheres being placed (indices `a` and `b`): pulls
/// them together with `weight`.
typedef Spring = ({int a, int b, double weight});

/// Moves overlapping spheres apart until none overlap.
///
/// [radii] and [positions] are parallel lists; [positions] is updated in
/// place. Spheres closer than `r_i + r_j + gap` are pushed apart (half each,
/// or all on the free one when the other is [pinned]). Neighbours are found
/// with a uniform grid, so a pass is close to linear. [containerRadius]
/// keeps every sphere inside `containerRadius - r - gap`, and [springs] pull
/// linked spheres together a little. Returns whether the final positions are
/// free of overlaps (with a zero gap).
bool relaxOverlaps(
  List<double> radii,
  List<Vec3> positions, {
  required double gap,
  required int iterations,
  required math.Random random,
  double? containerRadius,
  List<Spring> springs = const [],
  double springStrength = 0.02,
  int? pinned,
}) {
  final n = radii.length;
  if (n == 0) return true;
  final maxRadius = radii.reduce(math.max);
  final cell = 2 * maxRadius + gap;

  for (var iteration = 0; iteration < iterations; iteration++) {
    for (final (:a, :b, :weight) in springs) {
      final d = positions[b] - positions[a];
      final rest = radii[a] + radii[b] + gap;
      final length = d.length;
      if (length <= rest) continue;
      final move = d * (springStrength * weight * (length - rest) / length / 2);
      if (a != pinned) positions[a] = positions[a] + move;
      if (b != pinned) positions[b] = positions[b] - move;
    }

    var moved = false;
    final grid = <int, List<int>>{};
    int key(int cx, int cy, int cz) =>
        ((cx * 73856093) ^ (cy * 19349663) ^ (cz * 83492791)) & 0x3FFFFFFF;
    final cells = List.generate(n, (i) {
      final p = positions[i];
      final c = (
        (p.x / cell).floor(),
        (p.y / cell).floor(),
        (p.z / cell).floor(),
      );
      (grid[key(c.$1, c.$2, c.$3)] ??= []).add(i);
      return c;
    });
    for (var i = 0; i < n; i++) {
      final (cx, cy, cz) = cells[i];
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (var dz = -1; dz <= 1; dz++) {
            for (final j
                in grid[key(cx + dx, cy + dy, cz + dz)] ?? const <int>[]) {
              if (j <= i) continue;
              final minimum = radii[i] + radii[j] + gap;
              var d = positions[j] - positions[i];
              final length = d.length;
              if (length >= minimum) continue;
              moved = true;
              if (length == 0) {
                d = Vec3(
                  random.nextDouble() - 0.5,
                  random.nextDouble() - 0.5,
                  random.nextDouble() - 0.5,
                );
              }
              final push = d.withLength(minimum - length);
              if (i == pinned) {
                positions[j] = positions[j] + push;
              } else if (j == pinned) {
                positions[i] = positions[i] - push;
              } else {
                positions[i] = positions[i] - push * 0.5;
                positions[j] = positions[j] + push * 0.5;
              }
            }
          }
        }
      }
    }

    if (containerRadius != null) {
      for (var i = 0; i < n; i++) {
        final limit = containerRadius - radii[i] - gap;
        final p = positions[i];
        if (p.length > limit) positions[i] = p.withLength(math.max(0, limit));
      }
    }
    if (!moved && iteration > 0) break;
  }
  return hasNoOverlap(radii, positions, containerRadius: containerRadius);
}

/// Whether no two spheres overlap and, with [containerRadius], every
/// sphere is inside it.
bool hasNoOverlap(
  List<double> radii,
  List<Vec3> positions, {
  double? containerRadius,
}) {
  const epsilon = 1e-9;
  final n = radii.length;
  if (containerRadius != null) {
    for (var i = 0; i < n; i++) {
      if (positions[i].length + radii[i] > containerRadius + epsilon) {
        return false;
      }
    }
  }
  if (n < 2) return true;
  final maxRadius = radii.reduce(math.max);
  final cell = 2 * maxRadius;
  final grid = <(int, int, int), List<int>>{};
  for (var i = 0; i < n; i++) {
    final p = positions[i];
    (grid[(
              (p.x / cell).floor(),
              (p.y / cell).floor(),
              (p.z / cell).floor(),
            )] ??=
            [])
        .add(i);
  }
  for (final MapEntry(key: (cx, cy, cz), value: members) in grid.entries) {
    for (final i in members) {
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (var dz = -1; dz <= 1; dz++) {
            for (final j
                in grid[(cx + dx, cy + dy, cz + dz)] ?? const <int>[]) {
              if (j <= i) continue;
              if ((positions[i] - positions[j]).length + epsilon <
                  radii[i] + radii[j]) {
                return false;
              }
            }
          }
        }
      }
    }
  }
  return true;
}

/// Places spheres on a cubic lattice (spacing `2·max(r) + gap`): never
/// overlapping, whatever happens. The largest spheres take the lattice
/// points nearest the center. Returns the positions and the radius of the
/// smallest sphere centred on the origin that contains them with [gap].
({List<Vec3> positions, double radius}) latticePacking(
  List<double> radii, {
  required double gap,
}) {
  final n = radii.length;
  final spacing = 2 * radii.reduce(math.max) + gap;
  final side = (math.pow(n, 1 / 3) as double).ceil() + 1;
  final offset = (side - 1) / 2;
  final points = <Vec3>[
    for (var x = 0; x < side; x++)
      for (var y = 0; y < side; y++)
        for (var z = 0; z < side; z++)
          Vec3(
            (x - offset) * spacing,
            (y - offset) * spacing,
            (z - offset) * spacing,
          ),
  ]..sort((a, b) => a.length2.compareTo(b.length2));
  final order = List.generate(n, (i) => i)
    ..sort((a, b) {
      final byRadius = radii[b].compareTo(radii[a]);
      return byRadius != 0 ? byRadius : a.compareTo(b);
    });
  final positions = List<Vec3>.filled(n, Vec3.zero);
  var radius = 0.0;
  for (final (rank, i) in order.indexed) {
    positions[i] = points[rank];
    radius = math.max(radius, points[rank].length + radii[i] + gap);
  }
  return (positions: positions, radius: radius);
}
