# CshKit

CshKit is a pure Dart codec for Adobe Photoshop custom-shape libraries (`.csh`) and `CustomShapes.psp` preference files. It reads and writes editable vector geometry, exact preset metadata, optional group hierarchy, and opaque extension data without depending on Flutter or native code.

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
- Canonical CSH writing from decoded vector paths, including reconstructed hierarchy descriptors and opt-in preservation of compatible extensions.

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

final Uint8List output = CshEncoder.encode(library);
await File('shapes-copy.csh').writeAsBytes(output, flush: true);
```

Path coordinates are retained in Photoshop's source coordinate system. Helpers convert them to either a zero-based local rectangle or the absolute stored reference rectangle:

```dart
final CshShape shape = library.shapes.first;
final List<CshSubpath> localContours = shape.localSubpaths();
final List<CshSubpath> referenceContours = shape.referenceSubpaths();
```

Each knot contains an incoming handle, an on-curve anchor, and an outgoing handle. A closed contour connects its final knot back to its first knot. Consume `CshSubpath.operation`, `operationType`, `flags`, and `fillRule` when exact Photoshop composition matters.

## Reusable `dart:convert` API

`CshCodec` implements `Codec<CshFile, List<int>>` and keeps decoding and encoding policies together in one immutable value:

```dart
const CshCodec codec = CshCodec(
  decodeOptions: CshDecodeOptions(mode: CshDecodeMode.strict),
  encodeOptions: CshEncodeOptions(mode: CshEncodeMode.strict),
);

final CshFile library = codec.decode(bytes);
final Uint8List output = codec.encode(library);
```

The `List<int>` binary type allows composition with standard codecs such as `base64`; direct `encode` calls still return `Uint8List`. `CshEncoder` and `CshDecoder` are also configurable `Converter` implementations. Every conversion consumes or produces one complete in-memory CSH file rather than an incremental byte stream.

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

## Decoding and encoding policies

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

`CshEncoder.encode` writes canonical version 2 CSH output by default. Shape names, identifiers, bounds, and decoded paths are regenerated from the model, so preserved shape-record or path bytes are not required. Hierarchy descriptors are also regenerated when their tagged payload was not retained.

Use permissive output only when compatibility data from a tolerant decode must be reproduced:

```dart
final Uint8List output = CshEncoder.encode(
  library,
  options: const CshEncodeOptions(mode: CshEncodeMode.permissive),
);
```

Opaque tagged blocks and uninterpreted trailing bytes still require their preservation switches to have been enabled while decoding. `CshWriteException` reports model values or missing source data that cannot be represented safely.

The bundled inspector can validate one file or recursively inspect a corpus:

```console
dart run tool/inspect_csh.dart --strict --summary-only path/to/shapes
```

## Scope

CshKit reads and writes CSH files, but it does not rasterize Photoshop Boolean operations. A host editor remains responsible for applying combine, subtract, intersect, and exclude operations when rendering or converting the vector paths. Focale integration is intentionally left to a separate change.

See [docs/CSH.md](docs/CSH.md) for the implemented binary layout, record semantics, compatibility behavior, and integration notes.

## References

- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
- [Custom shapes file format notes](https://tonton-pixel.codeberg.page/photoshop-file-formats/custom-shapes-file-format.html)
- [ag-psd CSH implementation](https://github.com/Agamnentzar/ag-psd/blob/master/src/csh.ts)

CshKit is an independent implementation and is not affiliated with or endorsed by Adobe.
