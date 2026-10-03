# code_layout

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

Places every node of a [dart_code_3D](https://github.com/hawkbee1/dart_code_3d) code graph
in 3D: `CodeLayoutEngine().layout(graph)` turns a `CodeGraph` into a `CodeMap` (one
`Placement` per node: position relative to its parent's center, and radius). Pure Dart.

## Part of hawkbee

This repository is a git submodule of the
[hawkbee](https://github.com/hawkbee1/hawkbee) monorepo and **only builds inside it**:

```sh
git clone --recurse-submodules https://github.com/hawkbee1/hawkbee.git
cd hawkbee && flutter pub get
```

Design: hawkbee's [docs/dart_code_3d/architecture.md](https://github.com/hawkbee1/hawkbee/blob/main/docs/dart_code_3d/architecture.md) §6.

## Algorithm

1. **Radii, bottom-up**: a leaf's radius is `0.5·cbrt(loc)` (its volume grows with its code),
   clamped to 0.4–8; package spheres are 1.6, ghost parents at least 0.8. A container is large
   enough to hold its children (packing density 0.55, margin 1.25, and at least its largest
   child plus the gap).
2. **Inside each container**: children start on a Fibonacci sphere, largest first, then
   overlaps are relaxed on a spatial grid, with weak springs along calls between siblings. If
   they still do not fit, the container grows (up to 6 times), then falls back to a **cubic
   lattice that cannot overlap**. The invariants therefore always hold.
3. **Top level**: a 3D force simulation with a **Barnes–Hut octree** (`1/d²` repulsion), pulls
   towards the centroids of the same file, directory and package, springs along calls
   (`log(1 + count)`), the entry node's top-level ancestor **pinned at the origin**, and a
   cooling schedule. Remaining overlaps are relaxed; everything spreads out by 10% until none
   remain.
4. **External packages** sit on a shell just outside the project, each in the direction of the
   code that calls it, or evenly spread when that does not fit.

Everything is sorted by id first: the result does not depend on the order of the nodes, and
the random seed comes from the sorted ids (`stableHash`). On a given platform the same graph
always gives exactly the same layout. VM and JavaScript agree to about 1e-12.

Measured on 2026-10-04 (this container): flutter_scene 11,050 nodes in 5.2 s, AltMe 11,012 nodes
in 4.7 s, a generated 20,004-node project in 3.8 s. 0 overlaps, 0 spheres outside their parent.

## Developer CLI

```sh
dart run code_analysis_engine:analyze <folder> --out graph.json
dart run code_layout:layout graph.json --out map.dc3d     # or map.fscene (plain JSON)
```

The `.fscene` opens in the Flutter Scene Editor.

## Running tests

```sh
very_good test --coverage
```

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
