import 'dart:convert';
import 'dart:typed_data';

import 'package:cshkit/src/codec/csh_decoder.dart';
import 'package:cshkit/src/codec/csh_encoder.dart';
import 'package:cshkit/src/model/csh_file.dart';
import 'package:cshkit/src/model/csh_options.dart';

/// Converts CSH models to and from their binary representation.
///
/// Each conversion handles one complete in-memory file. The encoded type is
/// [List<int>] so this codec can be composed with standard `dart:convert`
/// codecs, while [encode] keeps the more precise [Uint8List] return type.
final class CshCodec extends Codec<CshFile, List<int>> {
  /// Options applied while decoding.
  final CshDecodeOptions decodeOptions;

  /// Options applied while encoding.
  final CshEncodeOptions encodeOptions;

  /// Creates a reusable codec with fixed decoding and encoding options.
  const CshCodec({
    this.decodeOptions = const CshDecodeOptions(),
    this.encodeOptions = const CshEncodeOptions(),
  });

  @override
  CshDecoder get decoder => CshDecoder(options: decodeOptions);

  @override
  CshEncoder get encoder => CshEncoder(options: encodeOptions);

  @override
  Uint8List encode(CshFile input) => encoder.convert(input);
}
