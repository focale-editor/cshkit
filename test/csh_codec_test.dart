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
}
