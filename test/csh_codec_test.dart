import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:cshkit/cshkit.dart';
import 'package:test/test.dart';

import 'support/csh_fixture_builder.dart';

/// Exercises the reusable `dart:convert` CSH interface.
void main() {
  group('CshCodec', () {
    test('converts complete files and composes with base64', () {
      const CshCodec codec = CshCodec(
        decodeOptions: CshDecodeOptions(mode: CshDecodeMode.strict),
        encodeOptions: CshEncodeOptions(mode: CshEncodeMode.strict),
      );
      final Uint8List bytes = CshFixtureBuilder.file(shapes: <Uint8List>[]);

      final CshFile file = codec.decode(bytes.toList(growable: false));
      final Uint8List encoded = codec.encode(file);
      final Codec<CshFile, String> base64Codec = codec.fuse(base64);
      final CshFile decodedBase64 = base64Codec.decode(base64Codec.encode(file));

      check(encoded).deepEquals(bytes);
      check(decodedBase64.shapes).isEmpty();
      check(codec.decoder.options.mode).equals(CshDecodeMode.strict);
      check(codec.encoder.options.mode).equals(CshEncodeMode.strict);
    });
  });

  test('reads and rewrites the keyed version 1 layout', () {
    // One closed square in the keyed record layout of Photoshop CS3's Talk Bubbles.csh.
    final CshVectorPath path = CshVectorPath.fromSubpaths(
      subpaths: const [
        CshSubpath(
          closed: true,
          knots: [
            CshBezierKnot.corner(anchor: CshPathPoint(x: 0, y: 0)),
            CshBezierKnot.corner(anchor: CshPathPoint(x: 1, y: 0)),
            CshBezierKnot.corner(anchor: CshPathPoint(x: 1, y: 1)),
            CshBezierKnot.corner(anchor: CshPathPoint(x: 0, y: 1)),
          ],
        ),
      ],
    );
    final Uint8List pathData = PsVectorPathCodec.encode(path);
    final PsBinaryWriter record = PsBinaryWriter()
      ..writeString('name')
      ..writeUint32(18)
      ..writeUint32(7)
      ..writeUint16List('Talk 10'.codeUnits)
      ..writeZeros(2)
      ..writeString('rect')
      ..writeUint32(16)
      ..writeInt32(0)
      ..writeInt32(0)
      ..writeInt32(10)
      ..writeInt32(20)
      ..writeString('data')
      ..writeUint32(pathData.length)
      ..writeBytes(pathData);
    final Uint8List body = record.takeBytes();
    final Uint8List bytes =
        (PsBinaryWriter()
              ..writeString('cush')
              ..writeUint32(1)
              ..writeUint32(0)
              ..writeUint32(1)
              ..writeUint32(body.length)
              ..writeBytes(body)
              ..writeZeros((4 - body.length % 4) % 4))
            .takeBytes();

    final CshFile file = CshDecoder.decode(bytes, options: const CshDecodeOptions(mode: CshDecodeMode.strict));

    check(file.version).equals(1);
    check(file.shapes.single.name).equals('Talk 10');
    check(file.shapes.single.bounds.width).equals(20);
    check(file.shapes.single.path?.subpaths.single.knots).isNotNull().length.equals(4);
    check(CshEncoder.encode(file)).deepEquals(bytes);
  });
}
