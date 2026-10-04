import 'dart:math' as math;

import 'package:code_graph/code_graph.dart';
import 'package:code_layout/src/octree.dart';
import 'package:code_layout/src/packing.dart';
import 'package:code_layout/src/vec3.dart';

/// Tuning of [CodeLayoutEngine]. The defaults suit 10–20k-node projects.
class LayoutOptions {
  /// Creates options.
  const new({
    this.locScale = 0.5,
    this.minRadius = 0.4,
    this.maxLeafRadius = 8,
    this.containerMargin = 1.25,
    this.gap = 0.2,
    this.innerIterations = 150,
    this.topIterations = 400,
    this.theta = 0.8,
    this.repulsion = 1,
    this.fileAttraction = 0.05,
    this.directoryAttraction = 0.02,
    this.packageAttraction = 0.005,
    this.linkStrength = 0.01,
    this.overlapIterations = 200,
  });

  /// `k` in a leaf's radius `k·cbrt(loc)`: volume grows like code length.
  final double locScale;

  /// Smallest radius.
  final double minRadius;

  /// Largest radius of a sphere without children.
  final double maxLeafRadius;

  /// Extra room in containers, times the packing radius.
  final double containerMargin;

  /// Minimum free space between spheres, and inside a container's shell.
  final double gap;

  /// Relaxation passes inside each container.
  final int innerIterations;

  /// Steps of the top-level force simulation.
  final int topIterations;

  /// Barnes–Hut opening angle (higher is faster and rougher).
  final double theta;

  /// Strength of the `1/d²` repulsion between top-level spheres.
  final double repulsion;

  /// Pull towards the centroid of the same file.
  final double fileAttraction;

  /// Pull towards the centroid of the same directory.
  final double directoryAttraction;

  /// Pull towards the centroid of the same package.
  final double packageAttraction;

  /// Strength of the springs along call links between top-level spheres.
  final double linkStrength;

  /// Relaxation passes removing the overlaps left by the simulation, before
  /// spreading everything out by 10% and trying again.
  final int overlapIterations;
}

/// Places every node of a [CodeGraph] in 3D (architecture §6).
///
/// Pure Dart and deterministic: on a given platform, the same graph gives
/// exactly the same placements, whatever the order of its nodes. Across
/// platforms (VM vs JavaScript) results agree to about 1e-12: `pow`, `sin`
/// and `cos` round differently. Maps are laid out once and stored, so this
/// never shows.
class CodeLayoutEngine {
  /// Creates the engine.
  const new();

  /// Lays out [graph]; [onProgress] receives fractions from 0 to 1.
  CodeMap layout(
    CodeGraph graph, {
    LayoutOptions options = const LayoutOptions(),
    void Function(double progress)? onProgress,
  }) => _Layout(graph, options, onProgress).run();
}

class _Layout {
  new(this.graph, this.options, this.onProgress)
    : random = math.Random(_seedOf(graph));

  final CodeGraph graph;
  final LayoutOptions options;
  final void Function(double progress)? onProgress;
  final math.Random random;

  final _radius = <String, double>{};
  final _relative = <String, Vec3>{};

  /// A seed from the sorted node ids (never `String.hashCode`, which is not
  /// stable across runs or platforms).
  static int _seedOf(CodeGraph graph) {
    final ids = graph.nodes.keys.toList()..sort();
    var seed = 0x811C9DC5;
    for (final id in ids) {
      seed = stableHash(id, seed: seed);
    }
    return seed;
  }

  List<CodeNode> _childrenOf(String? id) =>
      graph.childrenOf(id).toList()..sort((a, b) => a.id.compareTo(b.id));

  CodeMap run() {
    final top = _childrenOf(null)..forEach(_placeSubtree);
    onProgress?.call(0.3);
    _placeTopLevel(top);
    onProgress?.call(1);
    return CodeMap(
      graph: graph,
      placements: {
        for (final id in graph.nodes.keys)
          id: Placement(
            x: _relative[id]!.x,
            y: _relative[id]!.y,
            z: _relative[id]!.z,
            radius: _radius[id]!,
          ),
      },
    );
  }

  double _ownRadius(CodeNode node) => switch (node.kind) {
    CodeNodeKind.externalPackage => options.minRadius * 4,
    CodeNodeKind.ghostParent => options.minRadius * 2,
    _ => (options.locScale * math.pow(math.max(node.loc, 1), 1 / 3)).clamp(
      options.minRadius,
      options.maxLeafRadius,
    ),
  };

  /// Radii bottom-up, then children placed inside each container.
  void _placeSubtree(CodeNode node) {
    final children = _childrenOf(node.id)..forEach(_placeSubtree);
    final own = _ownRadius(node);
    if (children.isEmpty) {
      _radius[node.id] = own;
      return;
    }
    final radii = [for (final c in children) _radius[c.id]!];
    final gap = options.gap;
    final volume = radii.fold<double>(0, (sum, r) => sum + r * r * r);
    var radius = [
      own,
      math.pow(volume / 0.55, 1 / 3) * options.containerMargin,
      radii.reduce(math.max) + gap,
    ].reduce(math.max);

    final springs = _springsBetween(children);
    // Largest first on a Fibonacci sphere, then relaxed; grow if needed.
    final order = List.generate(children.length, (i) => i)
      ..sort((a, b) {
        final byRadius = radii[b].compareTo(radii[a]);
        return byRadius != 0 ? byRadius : a.compareTo(b);
      });
    List<Vec3>? positions;
    for (var attempt = 0; attempt < 6 && positions == null; attempt++) {
      final candidate = List<Vec3>.filled(children.length, Vec3.zero);
      for (final (rank, i) in order.indexed) {
        final room = math.max(0, radius - radii[i] - gap) * 0.7;
        candidate[i] = fibonacciDirection(rank, children.length) * room;
      }
      final fits = relaxOverlaps(
        radii,
        candidate,
        gap: gap,
        iterations: options.innerIterations,
        random: random,
        containerRadius: radius,
        springs: springs,
      );
      if (fits) {
        positions = candidate;
      } else {
        radius *= 1.15;
      }
    }
    if (positions == null) {
      final lattice = latticePacking(radii, gap: gap);
      positions = lattice.positions;
      radius = math.max(radius, lattice.radius);
    }
    for (final (i, child) in children.indexed) {
      _relative[child.id] = positions[i];
    }
    _radius[node.id] = radius;
  }

  /// Springs between [siblings] along call links between their subtrees.
  List<Spring> _springsBetween(List<CodeNode> siblings) {
    if (siblings.length < 2) return const [];
    final index = {for (final (i, n) in siblings.indexed) n.id: i};
    final weights = <(int, int), int>{};
    for (final sibling in siblings) {
      for (final link in graph.linksFrom(sibling.id)) {
        final j = index[link.toId];
        final i = index[sibling.id]!;
        if (j == null || j == i) continue;
        final key = i < j ? (i, j) : (j, i);
        weights[key] = (weights[key] ?? 0) + link.count;
      }
    }
    final keys = weights.keys.toList()
      ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    return [
      for (final k in keys)
        (a: k.$1, b: k.$2, weight: math.log(1 + weights[k]!)),
    ];
  }

  // ---------------------------------------------------------- top level

  void _placeTopLevel(List<CodeNode> top) {
    if (top.isEmpty) return;
    final internal = [
      for (final n in top)
        if (!n.isExternal || n.kind == CodeNodeKind.ghostParent) n,
    ];
    final packages = [
      for (final n in top)
        if (n.kind == CodeNodeKind.externalPackage) n,
    ];
    _simulate(internal);
    onProgress?.call(0.95);
    _placePackages(internal, packages);
  }

  void _simulate(List<CodeNode> nodes) {
    final n = nodes.length;
    if (n == 0) return;
    final index = {for (final (i, node) in nodes.indexed) node.id: i};
    final radii = [for (final node in nodes) _radius[node.id]!];
    final masses = [for (final r in radii) r * r + 1];
    final groups = [for (final node in nodes) _groupsOf(node)];

    final entry = _topAncestor(graph.project.entryNodeId);
    final pinned = entry == null ? null : index[entry];

    final volume = radii.fold<double>(0, (sum, r) => sum + r * r * r);
    final spread = math.pow(volume, 1 / 3) * 2.5 + 1;
    final positions = [
      for (var i = 0; i < n; i++)
        if (i == pinned)
          Vec3.zero
        else
          Vec3(
                random.nextDouble() * 2 - 1,
                random.nextDouble() * 2 - 1,
                random.nextDouble() * 2 - 1,
              ) *
              spread,
    ];
    final springs = _topSprings(index);

    final iterations = options.topIterations;
    final start = spread * 0.1;
    for (var step = 0; step < iterations; step++) {
      final temperature = start * (1 - step / iterations) + start * 0.01;
      final tree = Octree.build(positions, masses);
      final forces = [
        for (var i = 0; i < n; i++)
          tree.repulsionOn(i, theta: options.theta) * options.repulsion,
      ];
      for (final (level, strength) in [
        (0, options.fileAttraction),
        (1, options.directoryAttraction),
        (2, options.packageAttraction),
      ]) {
        final sums = <String, (Vec3, int)>{};
        for (var i = 0; i < n; i++) {
          final key = groups[i][level];
          if (key == null) continue;
          final (sum, count) = sums[key] ?? (Vec3.zero, 0);
          sums[key] = (sum + positions[i], count + 1);
        }
        for (var i = 0; i < n; i++) {
          final key = groups[i][level];
          if (key == null) continue;
          final (sum, count) = sums[key]!;
          if (count < 2) continue;
          forces[i] = forces[i] + (sum * (1 / count) - positions[i]) * strength;
        }
      }
      for (final (:a, :b, :weight) in springs) {
        final d = positions[b] - positions[a];
        final pull = d * (options.linkStrength * weight);
        forces[a] = forces[a] + pull;
        forces[b] = forces[b] - pull;
      }
      for (var i = 0; i < n; i++) {
        if (i == pinned) continue;
        final f = forces[i];
        final length = f.length;
        positions[i] =
            positions[i] +
            (length > temperature ? f * (temperature / length) : f);
      }
      if (step % 20 == 0) {
        onProgress?.call(0.3 + 0.6 * step / iterations);
      }
    }

    // Remove the remaining overlaps; spread out until none remain.
    while (!relaxOverlaps(
      radii,
      positions,
      gap: options.gap,
      iterations: options.overlapIterations,
      random: random,
      pinned: pinned,
    )) {
      for (var i = 0; i < n; i++) {
        positions[i] = positions[i] * 1.1;
      }
    }
    if (pinned != null) positions[pinned] = Vec3.zero;
    for (var i = 0; i < n; i++) {
      _relative[nodes[i].id] = positions[i];
    }
  }

  /// External packages on a shell outside the project, each in the
  /// direction of the code that uses it.
  void _placePackages(List<CodeNode> internal, List<CodeNode> packages) {
    if (packages.isEmpty) return;
    var projectRadius = 0.0;
    for (final node in internal) {
      projectRadius = math.max(
        projectRadius,
        _relative[node.id]!.length + _radius[node.id]!,
      );
    }
    final radii = [for (final p in packages) _radius[p.id]!];
    final directions = <Vec3>[];
    for (final (i, package) in packages.indexed) {
      var pull = Vec3.zero;
      for (final link in graph.linksTo(package.id)) {
        final from = _topAncestor(link.fromId);
        if (from != null && _relative[from] != null) {
          pull = pull + _relative[from]!;
        }
      }
      directions.add(
        pull.withLength(1, fallback: fibonacciDirection(i, packages.length)),
      );
    }
    final base = projectRadius + radii.reduce(math.max) * 2 + options.gap * 4;
    final padded = [for (final r in radii) r + options.gap / 2];
    bool tryShell(double shell) {
      final positions = [for (final d in directions) d * shell];
      if (!hasNoOverlap(padded, positions)) return false;
      for (final (i, package) in packages.indexed) {
        _relative[package.id] = positions[i];
      }
      return true;
    }

    // Towards the code that uses each package, slightly further out if
    // needed; when several point the same way, spread them evenly instead.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (tryShell(base * math.pow(1.15, attempt))) return;
    }
    for (var i = 0; i < directions.length; i++) {
      directions[i] = fibonacciDirection(i, directions.length);
    }
    var shell = base;
    while (!tryShell(shell)) {
      shell *= 1.15;
    }
  }

  List<Spring> _topSprings(Map<String, int> index) {
    final weights = <(int, int), int>{};
    for (final link in graph.links) {
      if (link.kind != LinkKind.call) continue;
      final a = index[_topAncestor(link.fromId)];
      final b = index[_topAncestor(link.toId)];
      if (a == null || b == null || a == b) continue;
      final key = a < b ? (a, b) : (b, a);
      weights[key] = (weights[key] ?? 0) + link.count;
    }
    final keys = weights.keys.toList()
      ..sort((x, y) => x.$1 != y.$1 ? x.$1 - y.$1 : x.$2 - y.$2);
    return [
      for (final k in keys)
        (a: k.$1, b: k.$2, weight: math.log(1 + weights[k]!)),
    ];
  }

  String? _topAncestor(String? id) {
    if (id == null || !graph.nodes.containsKey(id)) return null;
    var current = id;
    while (true) {
      final parent = graph.nodes[current]!.parentId;
      if (parent == null) return current;
      current = parent;
    }
  }

  /// File, directory and package of a top-level node; for a ghost parent,
  /// those of most of the classes inside it.
  List<String?> _groupsOf(CodeNode node) {
    var file = node.location?.filePath;
    var package = node.packageName;
    if (node.kind == CodeNodeKind.ghostParent) {
      final counts = <String, int>{};
      for (final child in graph.childrenOf(node.id)) {
        final path = child.location?.filePath;
        if (path != null) counts.update(path, (c) => c + 1, ifAbsent: () => 1);
      }
      final ranked = counts.entries.toList()
        ..sort(
          (a, b) =>
              b.value != a.value ? b.value - a.value : a.key.compareTo(b.key),
        );
      file = ranked.firstOrNull?.key;
      package = null;
    }
    final slash = file?.lastIndexOf('/') ?? -1;
    final directory = file == null
        ? null
        : (slash < 0 ? '' : file.substring(0, slash));
    return [file, directory, package];
  }
}
