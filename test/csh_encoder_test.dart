import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:cshkit/cshkit.dart';
import 'package:test/test.dart';

import 'support/csh_fixture_builder.dart';

/// Exercises canonical CSH writing and preserved compatibility output.
void main() {
  group('CshEncoder', () {
    test('rebuilds shape records without preserved path or record bytes', () {
      final Uint8List bytes = CshFixtureBuilder.file(
        shapes: <Uint8List>[
          CshFixtureBuilder.shape(
            name: 'Editable shape',
            id: 'shape-id',
            bounds: const CshRectangle(top: 0, left: 0, bottom: 100, right: 200),
            path: _path(),
          ),
        ],
      );
      final CshFile file = CshDecoder.decode(
        bytes,
        options: const CshDecodeOptions(
          mode: CshDecodeMode.strict,
          preservePathData: false,
          preserveShapeData: false,
        ),
      );

      final Uint8List encoded = CshEncoder.encode(file);

      check(encoded).deepEquals(bytes);
      check(CshDecoder.decode(encoded, options: const CshDecodeOptions(mode: CshDecodeMode.strict)).shapes.single.name).equals('Editable shape');
    });

    test('regenerates an unpreserved hierarchy descriptor', () {
      final Uint8List bytes = CshFixtureBuilder.file(
        shapes: <Uint8List>[
          CshFixtureBuilder.shape(
            name: 'Shape',
            id: 'shape-id',
            bounds: const CshRectangle(top: 0, left: 0, bottom: 10, right: 10),
            path: _path(),
          ),
        ],
        blocks: <CshTestTaggedBlock>[
          CshFixtureBuilder.hierarchyBlock(
            entries: <PsDescriptorValue>[
              CshFixtureBuilder.hierarchyObject(classId: 'preset', id: 'shape-id'),
            ],
          ),
        ],
      );
      final CshFile file = CshDecoder.decode(
        bytes,
        options: const CshDecodeOptions(
          mode: CshDecodeMode.strict,
          preserveTaggedBlockData: false,
        ),
      );

      final CshFile decoded = CshDecoder.decode(
        CshEncoder.encode(file),
        options: const CshDecodeOptions(mode: CshDecodeMode.strict),
      );

      check(decoded.hierarchy).length.equals(1);
      check(decoded.shapeFor(decoded.hierarchy.single)?.id).equals('shape-id');
    });

    test('validates and writes retained paths when path decoding was disabled', () {
      final Uint8List bytes = CshFixtureBuilder.file(
        shapes: <Uint8List>[
          CshFixtureBuilder.shape(
            name: 'Lazy shape',
            id: 'lazy-id',
            bounds: const CshRectangle(top: 0, left: 0, bottom: 10, right: 10),
            path: _path(),
          ),
        ],
      );
      final CshFile file = CshDecoder.decode(
        bytes,
        options: const CshDecodeOptions(
          mode: CshDecodeMode.strict,
          decodePathData: false,
          preserveShapeData: false,
        ),
      );

      check(CshEncoder.encode(file)).deepEquals(bytes);
    });

    test('permissive mode rejects a semantic identifier outside Latin-1', () {
      final CshFile sourceFile = CshDecoder.decode(
        CshFixtureBuilder.file(
          shapes: <Uint8List>[
            CshFixtureBuilder.shape(
              name: 'Shape',
              id: 'shape-id',
              bounds: const CshRectangle(top: 0, left: 0, bottom: 10, right: 10),
              path: _path(),
            ),
          ],
        ),
      );
      final CshShape source = sourceFile.shapes.single;
      final CshShape invalidShape = CshShape(
        index: source.index,
        sourceOffset: source.sourceOffset,
        name: source.name,
        nameCodeUnits: source.nameCodeUnits,
        namePaddingData: source.namePaddingData,
        version: source.version,
        declaredDataLength: source.declaredDataLength,
        id: 'snowman-☃',
        idData: Uint8List(0),
        bounds: source.bounds,
        path: source.path,
        pathData: source.pathData,
        pathRecordCount: source.pathRecordCount,
        pathPaddingData: source.pathPaddingData,
        recordData: source.recordData,
      );
      final CshFile invalidFile = CshFile(
        signature: sourceFile.signature,
        version: sourceFile.version,
        declaredShapeCount: sourceFile.declaredShapeCount,
        shapes: <CshShape>[invalidShape],
        hierarchy: sourceFile.hierarchy,
        hierarchyDescriptors: sourceFile.hierarchyDescriptors,
        taggedBlocks: sourceFile.taggedBlocks,
        trailingData: sourceFile.trailingData,
        trailingByteCount: sourceFile.trailingByteCount,
        warnings: sourceFile.warnings,
      );

      check(
        () => CshEncoder.encode(
          invalidFile,
          options: const CshEncodeOptions(mode: CshEncodeMode.permissive),
        ),
      ).throws<CshWriteException>();
    });

    test('keeps compatibility bytes only in permissive mode', () {
      final Uint8List bytes = CshFixtureBuilder.file(
        shapes: <Uint8List>[
          CshFixtureBuilder.shape(
            name: 'Shape',
            id: 'shape-id',
            bounds: const CshRectangle(top: 0, left: 0, bottom: 10, right: 10),
            path: _path(),
          ),
        ],
        blocks: <CshTestTaggedBlock>[
          CshFixtureBuilder.unknownBlock(signature: '8B64'),
        ],
        trailingData: const <int>[7, 8],
      );
      final CshFile file = CshDecoder.decode(bytes);

      check(() => CshEncoder.encode(file)).throws<CshWriteException>();
      check(
        CshEncoder.encode(
          file,
          options: const CshEncodeOptions(mode: CshEncodeMode.permissive),
        ),
      ).deepEquals(bytes);
    });
  });
}

/// Builds a canonical rectangular shape path.
CshVectorPath _path() => CshVectorPath.fromSubpaths(
  subpaths: <CshSubpath>[
    const CshSubpath(
      closed: true,
      knots: <CshBezierKnot>[
        CshBezierKnot.corner(anchor: CshPathPoint(x: 0, y: 0)),
        CshBezierKnot.corner(anchor: CshPathPoint(x: 1, y: 0)),
        CshBezierKnot.corner(anchor: CshPathPoint(x: 1, y: 1)),
      ],
    ),
  ],
);
