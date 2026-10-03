import 'dart:math' as math;

import 'package:code_layout/src/vec3.dart';

/// A Barnes–Hut octree: approximates the sum of `1/d²` repulsions from
/// many bodies in `O(log n)` per body.
class Octree {
  new _(this._root, this._positions, this._masses);

  /// Builds the tree of bodies at [positions] with [masses].
  factory build(List<Vec3> positions, List<double> masses) {
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;
    for (final p in positions) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      minZ = math.min(minZ, p.z);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
      maxZ = math.max(maxZ, p.z);
    }
    final root = positions.isEmpty
        ? _Cell(Vec3.zero, 1)
        : _Cell(
            Vec3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2),
            math.max(
                      math.max(maxX - minX, maxY - minY),
                      math.max(maxZ - minZ, 1e-9),
                    ) /
                    2 +
                1e-9,
          );
    for (var i = 0; i < positions.length; i++) {
      root.insert(i, positions, masses, 0);
    }
    return Octree._(root, positions, masses);
  }

  final _Cell _root;
  final List<Vec3> _positions;
  final List<double> _masses;

  /// The total repulsion on body [index]: `Σ m_i·m_j / d²` along the
  /// direction away from each other body (or cell, when a cell is seen under
  /// an angle smaller than [theta]). [softening] avoids infinite forces.
  Vec3 repulsionOn(int index, {double theta = 0.8, double softening = 1e-3}) {
    var fx = 0.0;
    var fy = 0.0;
    var fz = 0.0;
    final p = _positions[index];
    final m = _masses[index];
    void visit(_Cell cell) {
      if (cell.mass == 0) return;
      final bodies = cell.bodies;
      if (bodies != null) {
        for (final j in bodies) {
          if (j == index) continue;
          final d = p - _positions[j];
          final d2 = d.length2 + softening;
          final f = m * _masses[j] / (d2 * math.sqrt(d2));
          fx += d.x * f;
          fy += d.y * f;
          fz += d.z * f;
        }
        return;
      }
      final d = p - cell.massCenter;
      final d2 = d.length2 + softening;
      if ((2 * cell.half) * (2 * cell.half) < theta * theta * d2) {
        final f = m * cell.mass / (d2 * math.sqrt(d2));
        fx += d.x * f;
        fy += d.y * f;
        fz += d.z * f;
        return;
      }
      for (final child in cell.children!) {
        if (child != null) visit(child);
      }
    }

    visit(_root);
    return Vec3(fx, fy, fz);
  }
}

class _Cell {
  new(this.center, this.half);

  /// Cells this small keep several bodies instead of splitting forever
  /// (bodies at the same position).
  static const _maxDepth = 32;

  final Vec3 center;
  final double half;
  double mass = 0;
  double _mx = 0;
  double _my = 0;
  double _mz = 0;
  List<int>? bodies = [];
  List<_Cell?>? children;

  Vec3 get massCenter => Vec3(_mx / mass, _my / mass, _mz / mass);

  void insert(int i, List<Vec3> positions, List<double> masses, int depth) {
    final p = positions[i];
    final m = masses[i];
    mass += m;
    _mx += p.x * m;
    _my += p.y * m;
    _mz += p.z * m;
    final leaf = bodies;
    if (leaf != null) {
      if (leaf.isEmpty || depth >= _maxDepth) {
        leaf.add(i);
        return;
      }
      // Split: move the existing bodies down, then insert this one.
      bodies = null;
      children = List.filled(8, null);
      for (final j in leaf) {
        _child(positions[j]).insert(j, positions, masses, depth + 1);
      }
    }
    _child(p).insert(i, positions, masses, depth + 1);
  }

  _Cell _child(Vec3 p) {
    final index =
        (p.x >= center.x ? 1 : 0) |
        (p.y >= center.y ? 2 : 0) |
        (p.z >= center.z ? 4 : 0);
    final quarter = half / 2;
    return children![index] ??= _Cell(
      Vec3(
        center.x + (index & 1 == 0 ? -quarter : quarter),
        center.y + (index & 2 == 0 ? -quarter : quarter),
        center.z + (index & 4 == 0 ? -quarter : quarter),
      ),
      quarter,
    );
  }
}
