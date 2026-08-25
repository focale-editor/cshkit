import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:cshkit/cshkit.dart';
import 'package:test/test.dart';

import 'support/csh_fixture_builder.dart';

/// Exercises CSH geometry, hierarchy, compatibility, and resource limits.
void main() {
  group('CshDecoder', () {
    test('decodes exact metadata and semantic closed and open contours', () {
      final CshVectorPath sourcePath = _representativePath();
      final Uint8List bytes = CshFixtureBuilder.file(
        shapes: <Uint8List>[
          CshFixtureBuilder.shape(
            name: 'Étoile ★',
            id: '12345678-1234-1234-1234-123456789abc',
            bounds: const CshRectangle(
              top: -20,
              left: -10,
              bottom: 180,
              right: 190,
            ),
            path: sourcePath,
          ),
        ],
      );

      final CshFile file = CshDecoder.decode(
        bytes,
        options: const CshDecodeOptions(mode: CshDecodeMode.strict),
      );
      final CshShape shape = file.shapes.single;
      final List<CshSubpath> subpaths = shape.requirePath().subpaths;

      check(file.signature).equals('cush');
      check(file.version).equals(2);
      check(file.declaredShapeCount).equals(1);
      check(file.isComplete).isTrue();
      check(file.warnings).isEmpty();
      check(shape.name).equals('Étoile ★');
      check(shape.nameCodeUnits.last).equals(0);
      check(shape.id).equals('12345678-1234-1234-1234-123456789abc');
      check(shape.idData).deepEquals('12345678-1234-1234-1234-123456789abc'.codeUnits);
      check(shape.bounds.top).equals(-20);
      check(shape.bounds.left).equals(-10);
      check(shape.width).equals(200);
      check(shape.height).equals(200);
      check(shape.hasValidBounds).isTrue();
      check(shape.pathRecordCount).equals(sourcePath.records.length);
      check(shape.pathData).deepEquals(PsVectorPathCodec.encode(sourcePath));
      check(shape.recordData).isNotNull();
      check(subpaths).length.equals(2);
      check(subpaths.first.closed).isTrue();
      check(subpaths.first.operation).equals(-1);
      check(subpaths.first.operationType).isNull();
      check(subpaths.first.flags).equals(2);
      check(subpaths.first.fillRule).equals(CshPathFillRule.nonZero);
      check(subpaths.last.closed).isFalse();
      check(subpaths.last.operationType).equals(CshPathOperation.intersect);
      check(subpaths.last.knots.last.linked).isFalse();
      check(file.shapeById(shape.id)).identicalTo(shape);

      final CshPathPoint local = shape.localPoint(
        const CshPathPoint(x: 0.25, y: 0.5),
      );
      final CshPathPoint reference = shape.referencePoint(
        const CshPathPoint(x: 0.25, y: 0.5),
      );
      check(local.x).equals(50);
      check(local.y).equals(100);
      check(reference.x).equals(40);
      check(reference.y).equals(80);
      check(shape.localSubpaths().first.knots.first.anchor.x).isCloseTo(20, 0.00001);
      check(shape.referenceSubpaths().first.knots.first.anchor.x).isCloseTo(10, 0.00001);
    });

    test('maps nested phry hierarchy entries to source shapes', () {
      final Uint8List bytes = CshFixtureBuilder.file(
        shapes: <Uint8List>[
          _shape(name: 'First', id: 'first-id'),
          _shape(name: 'Second', id: 'second-id'),
        ],
        blocks: <CshTestTaggedBlock>[
          CshFixtureBuilder.hierarchyBlock(
            entries: <PsDescriptorValue>[
              CshFixtureBuilder.hierarchyObject(
                classId: 'Grup',
                name: 'Favorites',
                id: 'group-id',
              ),
              CshFixtureBuilder.hierarchyObject(
                classId: 'preset',
                id: 'first-id',
              ),
              CshFixtureBuilder.hierarchyObject(classId: 'preset'),
              CshFixtureBuilder.hierarchyObject(classId: 'groupEnd'),
            ],
          ),
        ],
      );

      final CshFile file = CshDecoder.decode(
        bytes,
        options: const CshDecodeOptions(mode: CshDecodeMode.strict),
      );

      check(file.taggedBlocks).length.equals(1);
      check(file.taggedBlocks.single.key).equals('phry');
      check(file.hierarchyDescriptors).length.equals(1);
      check(file.hierarchy).length.equals(4);
      check(file.hierarchy[0].kind).equals(CshHierarchyEntryKind.groupStart);
      check(file.hierarchy[0].name).equals('Favorites');
      check(file.hierarchy[0].id).equals('group-id');
      check(file.hierarchy[1].depth).equals(1);
      check(file.shapeFor(file.hierarchy[1])?.name).equals('First');
      check(file.shapeFor(file.hierarchy[2])?.name).equals('Second');
      check(file.hierarchy[3].kind).equals(CshHierarchyEntryKind.groupEnd);
      check(file.hierarchy[3].depth).equals(0);
      check(file.warnings).isEmpty();
    });

    test('preserves unknown 8BIM and 8B64 blocks with optional padding', () {
      final Uint8List bytes = CshFixtureBuilder.file(
        shapes: <Uint8List>[_shape(name: 'Shape', id: 'shape-id')],
        blocks: <CshTestTaggedBlock>[
          CshFixtureBuilder.unknownBlock(
            paddingData: Uint8List.fromList(<int>[0]),
          ),
          CshFixtureBuilder.unknownBlock(signature: '8B64'),
        ],
      );

      final CshFile file = CshDecoder.decode(bytes);

      check(file.taggedBlocks).length.equals(2);
      check(file.taggedBlocks.first.signature).equals('8BIM');
      check(file.taggedBlocks.first.paddingData).deepEquals(<int>[0]);
      check(file.taggedBlocks.last.signature).equals('8B64');
      check(file.taggedBlocks.last.declaredLength).equals(3);
      check(file.taggedBlocks.last.data).deepEquals(<int>[1, 2, 3]);
      check(file.trailingData).isEmpty();
      check(file.warnings).length.equals(3);
      check(
        () => CshDecoder.decode(
          bytes,
          options: const CshDecodeOptions(mode: CshDecodeMode.strict),
        ),
      ).throws<CshFormatException>();
    });

    test('can omit decoded and preserved bulk data independently', () {
      final Uint8List bytes = CshFixtureBuilder.file(
        shapes: <Uint8List>[_shape(name: 'Shape', id: 'shape-id')],
        blocks: <CshTestTaggedBlock>[CshFixtureBuilder.unknownBlock()],
        trailingData: const <int>[7, 8, 9],
      );

      final CshFile file = CshDecoder.decode(
        bytes,
        options: const CshDecodeOptions(
          decodePathData: false,
          preservePathData: false,
          preserveShapeData: false,
          preserveTaggedBlockData: false,
          preserveTrailingData: false,
        ),
      );
      final CshShape shape = file.shapes.single;

      check(shape.hasDecodedPath).isFalse();
      check(shape.pathData).isEmpty();
      check(shape.pathRecordCount).equals(_simplePath().records.length);
      check(shape.recordData).isNull();
      check(file.taggedBlocks.single.data).isEmpty();
      check(file.trailingData).isEmpty();
      check(file.trailingByteCount).equals(3);
      check(shape.requirePath).throws<StateError>();
    });

    test('reports duplicate identifiers and keeps the last shape lookup', () {
      final Uint8List bytes = CshFixtureBuilder.file(
        shapes: <Uint8List>[
          _shape(name: 'First', id: 'duplicate-id'),
          _shape(name: 'Second', id: 'duplicate-id'),
        ],
      );

      final CshFile file = CshDecoder.decode(bytes);

      check(file.warnings).length.equals(1);
      check(file.shapeById('duplicate-id')).identicalTo(file.shapes.last);
      check(
        () => CshDecoder.decode(
          bytes,
          options: const CshDecodeOptions(mode: CshDecodeMode.strict),
        ),
      ).throws<CshFormatException>();
    });

    test('turns recoverable extensions into warnings or strict failures', () {
      final List<Uint8List> variants = <Uint8List>[
        CshFixtureBuilder.file(
          version: 3,
          shapes: <Uint8List>[_shape(name: 'Shape', id: 'shape-id')],
        ),
        CshFixtureBuilder.file(
          shapes: <Uint8List>[
            CshFixtureBuilder.shape(
              name: 'Shape',
              id: 'shape-id',
              bounds: _bounds,
              path: _simplePath(),
              version: 2,
            ),
          ],
        ),
        CshFixtureBuilder.file(
          shapes: <Uint8List>[
            CshFixtureBuilder.shape(
              name: 'Shape',
              id: 'shape-id',
              bounds: _bounds,
              path: _simplePath(),
              terminateName: false,
            ),
          ],
        ),
        CshFixtureBuilder.file(
          shapes: <Uint8List>[
            CshFixtureBuilder.shape(
              name: 'Shape',
              id: 'shape-id',
              bounds: _bounds,
              path: CshVectorPath(
                records: <CshPathRecord>[
                  CshUnknownPathRecord(
                    selector: 42,
                    data: Uint8List(24),
                  ),
                ],
              ),
            ),
          ],
        ),
        CshFixtureBuilder.file(
          shapes: <Uint8List>[_shape(name: 'Shape', id: 'shape-id')],
          trailingData: const <int>[1, 2, 3],
        ),
      ];

      for (final Uint8List variant in variants) {
        check(CshDecoder.decode(variant).warnings).isNotEmpty();
        check(
          () => CshDecoder.decode(
            variant,
            options: const CshDecodeOptions(mode: CshDecodeMode.strict),
          ),
        ).throws<CshFormatException>();
      }
    });

    test('rejects malformed headers, truncation, and unsafe resource sizes', () {
      final Uint8List shape = _shape(name: 'Shape', id: 'shape-id');
      final Uint8List valid = CshFixtureBuilder.file(
        shapes: <Uint8List>[shape],
      );
      final Uint8List wrongSignature = CshFixtureBuilder.file(
        signature: 'NOPE',
        shapes: <Uint8List>[shape],
      );
      final Uint8List excessiveCount = CshFixtureBuilder.file(
        declaredShapeCount: 2,
        shapes: <Uint8List>[shape],
      );
      final Uint8List tagged = CshFixtureBuilder.file(
        shapes: <Uint8List>[shape],
        blocks: <CshTestTaggedBlock>[CshFixtureBuilder.unknownBlock()],
      );
      final Uint8List hierarchy = CshFixtureBuilder.file(
        shapes: <Uint8List>[shape],
        blocks: <CshTestTaggedBlock>[
          CshFixtureBuilder.hierarchyBlock(
            entries: <PsDescriptorValue>[
              CshFixtureBuilder.hierarchyObject(classId: 'preset'),
            ],
          ),
        ],
      );
      final Uint8List truncated = Uint8List.sublistView(valid, 0, valid.length - 1);

      check(() => CshDecoder.decode(Uint8List(0))).throws<CshFormatException>();
      check(() => CshDecoder.decode(wrongSignature)).throws<CshFormatException>();
      check(
        () => CshDecoder.decode(
          excessiveCount,
          options: const CshDecodeOptions(maxShapes: 1),
        ),
      ).throws<CshFormatException>();
      check(
        () => CshDecoder.decode(
          valid,
          options: CshDecodeOptions(maxFileBytes: valid.length - 1),
        ),
      ).throws<CshFormatException>();
      check(
        () => CshDecoder.decode(
          valid,
          options: const CshDecodeOptions(maxShapeNameCodeUnits: 2),
        ),
      ).throws<CshFormatException>();
      check(
        () => CshDecoder.decode(
          valid,
          options: const CshDecodeOptions(maxShapeBytes: 1),
        ),
      ).throws<CshFormatException>();
      check(
        () => CshDecoder.decode(
          valid,
          options: const CshDecodeOptions(maxDimension: 10),
        ),
      ).throws<CshFormatException>();
      check(
        () => CshDecoder.decode(
          valid,
          options: const CshDecodeOptions(maxPathRecords: 1),
        ),
      ).throws<CshFormatException>();
      check(
        () => CshDecoder.decode(
          tagged,
          options: const CshDecodeOptions(maxTaggedBlockBytes: 2),
        ),
      ).throws<CshFormatException>();
      check(
        () => CshDecoder.decode(
          hierarchy,
          options: const CshDecodeOptions(
            mode: CshDecodeMode.strict,
            maxHierarchyEntries: 0,
          ),
        ),
      ).throws<CshFormatException>();
      check(
        () => CshDecoder.decode(
          hierarchy,
          options: const CshDecodeOptions(
            descriptorOptions: PsDescriptorDecodeOptions(maxValues: 0),
          ),
        ),
      ).throws<CshFormatException>();
      check(
        () => CshDecoder.decode(
          truncated,
          options: const CshDecodeOptions(mode: CshDecodeMode.strict),
        ),
      ).throws<CshFormatException>();
      check(
        () => CshDecoder.decode(
          valid,
          options: const CshDecodeOptions(maxShapes: -1),
        ),
      ).throws<ArgumentError>();
      check(
        () => CshDecoder.decode(
          valid,
          options: const CshDecodeOptions(
            descriptorOptions: PsDescriptorDecodeOptions(maxDepth: -1),
          ),
        ),
      ).throws<ArgumentError>();
    });

    test('returns partial tolerant results for a truncated declared shape list', () {
      final Uint8List bytes = CshFixtureBuilder.file(
        declaredShapeCount: 2,
        shapes: <Uint8List>[_shape(name: 'Shape', id: 'shape-id')],
      );

      final CshFile file = CshDecoder.decode(bytes);

      check(file.shapes).length.equals(1);
      check(file.isComplete).isFalse();
      check(file.warnings).length.equals(1);
      check(
        () => CshDecoder.decode(
          bytes,
          options: const CshDecodeOptions(mode: CshDecodeMode.strict),
        ),
      ).throws<CshFormatException>();
    });
  });
}

/// Reference rectangle shared by compact synthetic shapes.
const CshRectangle _bounds = CshRectangle(
  top: 0,
  left: 0,
  bottom: 100,
  right: 200,
);

/// Builds one simple custom-shape record.
Uint8List _shape({
  required String name,
  required String id,
}) => CshFixtureBuilder.shape(
  name: name,
  id: id,
  bounds: _bounds,
  path: _simplePath(),
);

/// Builds one valid closed rectangular contour.
CshVectorPath _simplePath() => CshVectorPath.fromSubpaths(
  subpaths: <CshSubpath>[
    const CshSubpath(
      closed: true,
      knots: <CshBezierKnot>[
        CshBezierKnot.corner(anchor: CshPathPoint(x: 0, y: 0)),
        CshBezierKnot.corner(anchor: CshPathPoint(x: 1, y: 0)),
        CshBezierKnot.corner(anchor: CshPathPoint(x: 1, y: 1)),
        CshBezierKnot.corner(anchor: CshPathPoint(x: 0, y: 1)),
      ],
    ),
  ],
);

/// Builds contours covering signed operations, flags, and knot selectors.
CshVectorPath _representativePath() => CshVectorPath.fromSubpaths(
  startsWithAllPixels: true,
  subpaths: <CshSubpath>[
    const CshSubpath(
      closed: true,
      operation: -1,
      flags: 2,
      knots: <CshBezierKnot>[
        CshBezierKnot.corner(anchor: CshPathPoint(x: 0.1, y: 0.2)),
        CshBezierKnot(
          incoming: CshPathPoint(x: 0.6, y: 0.1),
          anchor: CshPathPoint(x: 0.8, y: 0.2),
          outgoing: CshPathPoint(x: 0.9, y: 0.3),
        ),
      ],
    ),
    const CshSubpath(
      closed: false,
      operation: 3,
      knots: <CshBezierKnot>[
        CshBezierKnot.corner(anchor: CshPathPoint(x: -0.25, y: 0.5)),
        CshBezierKnot.corner(anchor: CshPathPoint(x: 1.25, y: 0.75)),
      ],
    ),
  ],
);
