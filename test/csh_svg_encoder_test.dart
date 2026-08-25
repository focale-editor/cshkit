import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:cshkit/cshkit.dart';
import 'package:test/test.dart';

import 'support/csh_fixture_builder.dart';

/// Exercises SVG coordinate conversion, formatting, and validation.
void main() {
  group('CshSvgEncoder', () {
    test('emits normalized, local, and reference path coordinates', () {
      final CshShape shape = _decodedShape();

      final String normalized = CshSvgEncoder.pathData(
        shape,
        coordinateSpace: CshSvgCoordinateSpace.normalized,
        fractionDigits: 2,
      );
      final String local = CshSvgEncoder.pathData(
        shape,
        coordinateSpace: CshSvgCoordinateSpace.local,
        fractionDigits: 2,
      );
      final String reference = CshSvgEncoder.pathData(
        shape,
        coordinateSpace: CshSvgCoordinateSpace.reference,
        fractionDigits: 2,
      );

      check(normalized).equals('M0,0C0,0 1,0 1,0C1,0 1,1 1,1C1,1 0,0 0,0Z');
      check(local).equals('M0,0C0,0 200,0 200,0C200,0 200,100 200,100C200,100 0,0 0,0Z');
      check(reference).equals('M-10,-20C-10,-20 190,-20 190,-20C190,-20 190,80 190,80C190,80 -10,-20 -10,-20Z');
    });

    test('creates a standalone escaped SVG preview', () {
      final String svg = CshSvgEncoder.document(
        _decodedShape(),
        coordinateSpace: CshSvgCoordinateSpace.reference,
        fill: 'red & "blue"',
      );

      check(svg).startsWith('<svg xmlns="http://www.w3.org/2000/svg" viewBox="-10 -20 200 100">');
      check(svg).contains('fill="red &amp; &quot;blue&quot;"');
      check(svg).endsWith(' fill-rule="evenodd"/></svg>');
    });

    test('rejects invalid precision and invalid reference bounds', () {
      final CshShape shape = _decodedShape();
      final CshShape invalid = CshDecoder.decode(
        CshFixtureBuilder.file(
          shapes: <Uint8List>[
            CshFixtureBuilder.shape(
              name: 'Invalid',
              id: 'invalid-id',
              bounds: const CshRectangle(
                top: 0,
                left: 0,
                bottom: 0,
                right: 100,
              ),
              path: _path(),
            ),
          ],
        ),
      ).shapes.single;

      check(
        () => CshSvgEncoder.pathData(shape, fractionDigits: 21),
      ).throws<RangeError>();
      check(() => CshSvgEncoder.document(invalid)).throws<StateError>();
    });
  });
}

/// Decodes one deterministic triangular shape used by SVG checks.
CshShape _decodedShape() => CshDecoder.decode(
  CshFixtureBuilder.file(
    shapes: <Uint8List>[
      CshFixtureBuilder.shape(
        name: 'Triangle',
        id: 'triangle-id',
        bounds: const CshRectangle(
          top: -20,
          left: -10,
          bottom: 80,
          right: 190,
        ),
        path: _path(),
      ),
    ],
  ),
).shapes.single;

/// Builds the closed contour used by SVG checks.
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
