# CSH format support

This document describes the CSH structures accepted by CshKit and the semantic model exposed to applications. Multibyte integers are big-endian unless stated otherwise.

## Container layout

A standalone custom-shape library and Photoshop's `CustomShapes.psp` preference file use the same leading container:

| Field | Type | Meaning |
| --- | --- | --- |
| Signature | 4 bytes | ASCII `cush` |
| Version | `uint32` | Defined value is 2 |
| Shape count | `uint32` | Number of following shape records |
| Shapes | variable | Consecutive records without an outer table |
| Trailer | variable | Optional tagged blocks or opaque bytes |

CshKit verifies every declared length before reading its contents. A tolerant decode can return the shapes that precede a damaged later record; `CshFile.isComplete` distinguishes that result from a fully decoded library.

## Shape record

Each shape starts with a name and an independently length-bounded body:

| Field | Type | Meaning |
| --- | --- | --- |
| Name length | `uint32` | Number of following UTF-16 code units, normally including a terminal null |
| Name | `uint16[]` | Big-endian UTF-16 code units |
| Name padding | 0–3 bytes | Alignment to a four-byte boundary |
| Record version | `uint32` | Defined value is 1 |
| Body length | `uint32` | Number of following body bytes |
| Identifier length | `uint8` | Number of one-byte identifier characters |
| Identifier | bytes | Usually a UUID, stored as a Pascal string |
| Top, left, bottom, right | four `int32` values | Signed reference rectangle |
| Path records | 26-byte records | Vector geometry and ancillary path state |
| Body padding | normally 0–3 bytes | Bytes not forming a complete path record |

`CshShape.name` removes terminal nulls for application use while `nameCodeUnits` keeps the exact sequence. The same distinction is available for `id` and `idData`. Name padding, path padding, path bytes, and optionally the complete record remain available for compatibility work.

Bounds use inclusive top and left edges with exclusive bottom and right edges. Width is `right - left`; height is `bottom - top`. Negative origins are valid. Non-positive dimensions are a compatibility issue because they cannot define a useful SVG view box.

## Path records

Every path record is exactly 26 bytes: a two-byte selector followed by a 24-byte payload.

| Selector | Typed model | Meaning |
| --- | --- | --- |
| 0 | `CshSubpathLengthRecord` | Closed-subpath length |
| 1 | `CshBezierKnotRecord` | Closed linked knot |
| 2 | `CshBezierKnotRecord` | Closed unlinked knot |
| 3 | `CshSubpathLengthRecord` | Open-subpath length |
| 4 | `CshBezierKnotRecord` | Open linked knot |
| 5 | `CshBezierKnotRecord` | Open unlinked knot |
| 6 | `CshPathFillRuleRecord` | Path fill-rule state |
| 7 | `CshPathClipboardRecord` | Clipboard bounds and resolution |
| 8 | `CshPathInitialFillRecord` | Initial filled-canvas state |
| Other | `CshUnknownPathRecord` | Exact opaque 24-byte payload |

A subpath-length payload begins with its unsigned knot count, signed operation, 16-bit flags, and 18 reserved bytes. The following declared number of knot records form one semantic `CshSubpath`. CshKit preserves malformed ordering as raw records and reports the mismatch instead of inventing missing geometry.

The signed operation has these known meanings:

| Value | `CshPathOperation` | Meaning |
| ---: | --- | --- |
| -1 | no typed value | Unspecified operation used by some CSH writers |
| 0 | `exclude` | Exclude overlap with accumulated geometry |
| 1 | `combine` | Add to accumulated geometry |
| 2 | `subtract` | Remove from accumulated geometry |
| 3 | `intersect` | Keep only overlap with accumulated geometry |

The original integer remains in `CshSubpath.operation`, including unknown extensions. `operationType` is nullable so callers cannot accidentally treat `-1` or an unknown operation as `combine`.

The flags are retained verbatim. The value 2 selects the non-zero fill rule in known Photoshop data; other values use the even-odd interpretation while remaining accessible through `flags`.

## Bézier coordinates

A knot stores three points in this order:

1. incoming control handle;
2. on-curve anchor;
3. outgoing control handle.

Each point is stored vertically and then horizontally as two signed 8.24 fixed-point numbers. The representable range is -128 through almost 128; Adobe documents path coordinates in the narrower -16 through 16 interval. CshKit decodes the complete representable range and reports coordinates outside the documented interval as compatibility issues.

Coordinates are usually normalized against the reference rectangle but are not clamped. Shapes can intentionally extend below 0 or above 1.

For a normalized point `(x, y)`, the provided conversions are:

```text
localX = x * (right - left)
localY = y * (bottom - top)

referenceX = left + localX
referenceY = top + localY
```

The segment arriving at knot `n` uses the outgoing handle of knot `n - 1` and the incoming handle of knot `n`. Closed contours also create the final-to-first segment. `CshBezierKnot.linked` records Photoshop's editing constraint; it does not alter the stored control points.

## Tagged trailer blocks and hierarchy

After the declared shapes, CSH files can contain Photoshop tagged blocks:

| Signature | Length field | Support |
| --- | --- | --- |
| `8BIM` | `uint32` | Decoded and preserved |
| `8B64` | `uint64` | Decoded and preserved as an extension |

The signature is followed by a four-byte key, the length, and the unpadded payload. Some writers align a payload to four bytes and others omit final padding. CshKit only consumes zero padding when it leads to another recognizable block or exactly reaches end-of-file, avoiding accidental loss of opaque trailer data.

The `phry` key contains a `uint32` descriptor version, normally 16, followed by a Photoshop Action Descriptor. The root `hierarchy` list is mapped to:

- group starts (`Grup`, `group`, or `groupStart`);
- group ends (`groupEnd`);
- presets (`preset`);
- empty slots;
- unknown descriptor classes.

Preset identifiers are matched to shape identifiers first, with source-order fallback for descriptors that omit an identifier. The complete descriptors remain in `CshFile.hierarchyDescriptors`, so future class variants are not hidden by the typed view.

## Compatibility modes

Tolerant mode preserves as much safely bounded information as possible and emits `CshWarning` values. It covers unknown versions, selectors, operations, tagged keys, alternate signatures, non-zero padding, malformed optional hierarchy data, unexpected reserved bytes, and unrecognized trailer data.

Strict mode rejects the first such issue with `CshFormatException`. It is useful for corpus validation and deterministic import pipelines.

Configured safety limits are never downgraded to warnings. They protect:

- total input bytes;
- shape count and aggregate path-record count;
- shape-name and shape-body lengths;
- reference dimensions;
- tagged-block payloads;
- hierarchy entries;
- Action Descriptor depth and aggregate values.

## Preservation and memory use

Decoded geometry and preserved source bytes serve different purposes and can be controlled independently:

| Option | Disabled result |
| --- | --- |
| `decodePathData` | `CshShape.path` is `null`; record count and metadata remain |
| `preservePathData` | `CshShape.pathData` is empty |
| `preserveShapeData` | `CshShape.recordData` is `null` |
| `preserveTaggedBlockData` | Tagged payloads are empty, but recognized hierarchy is still decoded |
| `preserveTrailingData` | `trailingData` is empty while `trailingByteCount` remains accurate |

For UI browsing, decode on a worker isolate when libraries are large. Metadata-only decoding avoids allocating semantic knot objects. For editing, retain the semantic path but consider disabling `preservePathData` and `preserveShapeData` unless exact source reconstruction is required.

## Encoding

`CshEncoder` writes the `cush` envelope, shape records, vector-path records, tagged blocks, and hierarchy descriptors. Strict mode is the default and emits canonical version 2 containers with version 1 shapes, regenerated lengths, zero alignment, and validated Photoshop path coordinates. It uses the decoded `CshVectorPath`, so complete source records and preserved path bytes are unnecessary for ordinary editing and writing.

Permissive mode retains representable source versions, declared lengths, alignment bytes, alternate tagged-block signatures, and unrecognized trailing data. Opaque data can only be emitted when the corresponding decode preservation option retained it. Both modes report unrepresentable models through `CshWriteException` rather than truncating numeric or Pascal-string fields.

## Integration guidance

An editor should use the typed subpaths as its canonical import representation. SVG text is suitable for previews, but cannot carry the per-subpath Boolean operation by itself. Retain the CSH identifier as the stable preset key and the source index as an ordering fallback. Use the flattened hierarchy to build a tree without assuming that every preset descriptor contains a name or identifier.

CshKit has no Flutter dependency. Focale can therefore decode in an isolate, translate `CshBezierKnot` values into its own vector model, and keep parser-specific bytes outside presentation state.

## Current boundaries

CshKit does not rasterize contours or perform Boolean geometry. Unknown structures are kept accessible rather than silently interpreted. Tolerant decoding stops at a structurally damaged shape when no reliable boundary remains; it does not scan arbitrary bytes for a guessed recovery point. Encoding likewise requires complete semantic or preserved data and never invents an opaque payload.

## References

- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
- [Custom shapes file format notes](https://tonton-pixel.codeberg.page/photoshop-file-formats/custom-shapes-file-format.html)
- [ag-psd CSH source](https://github.com/Agamnentzar/ag-psd/blob/master/src/csh.ts)
