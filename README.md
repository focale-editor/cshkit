# CshKit

CshKit is a pure Dart reader for Adobe Photoshop custom-shape libraries (`.csh`) and `CustomShapes.psp` preference files. It exposes editable vector geometry, exact preset metadata, optional group hierarchy, and opaque extension data without depending on Flutter or native code.

The package is intended for editors such as Focale that need more than a raster thumbnail: stable shape identifiers, cubic Bézier contours, Photoshop Boolean-operation markers, source bounds, and bounded decoding of untrusted files.

## Supported data

- `cush` version 2 containers and version 1 custom-shape records.
- Big-endian UTF-16 names, Pascal identifiers, signed reference rectangles, and exact source records.
- Closed and open subpaths, linked and unlinked cubic Bézier knots, and all defined Photoshop path selectors from 0 through 8.
- Signed 8.24 fixed-point coordinates, including values outside the usual normalized 0–1 interval.
- Subpath operation values `-1`, exclude, combine, subtract, and intersect, plus the original undocumented flags.
- Fill-rule, initial-fill, and clipboard records, with reserved payload bytes retained.
- Version 16 `phry` Action Descriptors containing nested groups, group ends, presets, names, and identifiers.
- `8BIM` and `8B64` tagged blocks, unknown path selectors, unknown descriptor classes, padding, and trailing bytes preserved for forward compatibility.
- Strict and tolerant modes with configurable limits for file size, shapes, dimensions, names, shape bodies, path records, descriptors, hierarchy entries, and tagged blocks.

## Usage

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:cshkit/cshkit.dart';

final Uint8List bytes = await File('shapes.csh').readAsBytes();
final CshFile library = CshDecoder.decode(bytes);

for (final CshShape shape in library.shapes) {
  final CshVectorPath path = shape.requirePath();
  print('${shape.name}: ${path.subpaths.length} contours (${shape.id})');
}
```

Path coordinates are retained in Photoshop's source coordinate system. Helpers convert them to either a zero-based local rectangle or the absolute stored reference rectangle:

```dart
final CshShape shape = library.shapes.first;
final List<CshSubpath> localContours = shape.localSubpaths();
final List<CshSubpath> referenceContours = shape.referenceSubpaths();
```

Each knot contains an incoming handle, an on-curve anchor, and an outgoing handle. A closed contour connects its final knot back to its first knot. Consume `CshSubpath.operation`, `operationType`, `flags`, and `fillRule` when exact Photoshop composition matters.

## SVG previews

The dependency-free SVG helper is useful for diagnostics and thumbnails:

```dart
final String svg = CshSvgEncoder.document(
  library.shapes.first,
  coordinateSpace: CshSvgCoordinateSpace.local,
);
```

An SVG path string does not encode Photoshop's per-contour combine, subtract, intersect, or exclude operations. `CshSvgEncoder` therefore uses even-odd filling as a portable preview convention; an editor should apply the typed operations itself when exact composition is required.

## Hierarchy

Newer libraries can append a `phry` hierarchy. `CshFile.hierarchy` is a flattened ordered sequence of group starts, group ends, presets, empty entries, and unknown entries. Presets resolve directly to their source shapes:

```dart
for (final CshHierarchyEntry entry in library.hierarchy) {
  final CshShape? shape = library.shapeFor(entry);
  if (shape != null) {
    print('${'  ' * entry.depth}${shape.name}');
  }
}
```

The complete generic `PsDescriptor` is also retained for every hierarchy block.

## Strict, tolerant, and memory-bounded decoding

Tolerant decoding is the default. Recoverable extensions and damaged optional metadata are preserved where possible and reported through `CshFile.warnings`. Strict mode turns every compatibility warning into a `CshFormatException`:

```dart
final CshFile library = CshDecoder.decode(
  bytes,
  options: const CshDecodeOptions(mode: CshDecodeMode.strict),
);
```

Safety limits always fail instead of being downgraded to warnings. Preservation switches are independent:

- `decodePathData` controls semantic path decoding;
- `preservePathData` retains the exact 26-byte record stream;
- `preserveShapeData` retains each complete shape record;
- `preserveTaggedBlockData` retains tagged-block payloads;
- `preserveTrailingData` retains unrecognized trailer bytes.

For a metadata-only browser, disable path decoding and the preservation switches. For an editor, keep path decoding enabled but disable redundant source copies unless round-trip writing or forensic inspection is planned.

The bundled inspector can validate one file or recursively inspect a corpus:

```console
dart run tool/inspect_csh.dart --strict --summary-only path/to/shapes
```

## Scope

CshKit currently reads CSH files but does not write them or rasterize Photoshop Boolean operations. Its model retains the metadata and opaque bytes needed to add those features later without narrowing the reader. Focale integration is intentionally left to a separate change.

See [docs/CSH.md](docs/CSH.md) for the implemented binary layout, record semantics, compatibility behavior, and integration notes.

## References

- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
- [Custom shapes file format notes](https://tonton-pixel.codeberg.page/photoshop-file-formats/custom-shapes-file-format.html)
- [ag-psd CSH implementation](https://github.com/Agamnentzar/ag-psd/blob/master/src/csh.ts)

CshKit is an independent implementation and is not affiliated with or endorsed by Adobe.
