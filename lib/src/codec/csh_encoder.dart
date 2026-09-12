import 'dart:convert';
import 'dart:typed_data';

import 'package:cshkit/src/model/csh_file.dart';
import 'package:cshkit/src/model/csh_options.dart';
import 'package:cshkit/src/model/csh_shape.dart';
import 'package:pscore/pscore.dart';

/// Encodes immutable CSH models into Photoshop custom-shape libraries.
///
/// The configured instance is a one-shot [Converter] for complete in-memory
/// files. Use [encode] when conversion options are supplied per call.
final class CshEncoder extends Converter<CshFile, List<int>> {
  /// Options applied by [convert].
  final CshEncodeOptions options;

  /// Creates a reusable encoder with fixed [options].
  const CshEncoder({
    this.options = const CshEncodeOptions(),
  });

  @override
  Uint8List convert(CshFile input) => encode(input, options: options);

  /// Canonical CSH container signature.
  static const String _fileSignature = 'cush';

  /// Canonical CSH container version.
  static const int _fileVersion = 2;

  /// Canonical custom-shape record version.
  static const int _shapeVersion = 1;

  /// Canonical hierarchy Action Descriptor version.
  static const int _descriptorVersion = 16;

  /// Encodes [file] into a new big-endian CSH byte buffer.
  static Uint8List encode(
    CshFile file, {
    CshEncodeOptions options = const CshEncodeOptions(),
  }) {
    try {
      _validateRepresentable(file, options);
      if (options.mode == CshEncodeMode.strict) {
        _validateStrict(file, options);
      }

      final PsBinaryWriter writer = PsBinaryWriter()
        ..writeString(file.signature)
        ..writeUint32(file.version)
        ..writeUint32(options.mode == CshEncodeMode.strict ? file.shapes.length : file.declaredShapeCount);
      for (final CshShape shape in file.shapes) {
        writer.writeBytes(_encodeShape(shape, options));
      }
      if (options.includeTaggedBlocks) {
        _writeTaggedBlocks(writer, file, options);
      }
      if (options.includeTrailingData) {
        writer.writeBytes(file.trailingData);
      }
      return writer.takeBytes();
    } on CshWriteException {
      rethrow;
    } on PsWriteException catch (error) {
      throw CshWriteException(message: error.message);
    } on RangeError catch (error) {
      throw CshWriteException(message: 'A CSH numeric value cannot be encoded: $error');
    }
  }

  /// Encodes one custom shape from semantic fields or preserved source data.
  static Uint8List _encodeShape(CshShape shape, CshEncodeOptions options) {
    final Uint8List? preservedRecord = shape.recordData;
    final bool hasPathSource = shape.path != null || shape.pathData.isNotEmpty;
    if (!hasPathSource) {
      if (options.mode == CshEncodeMode.permissive && preservedRecord != null) {
        return preservedRecord;
      }
      throw CshWriteException(
        message: 'Shape ${shape.index + 1} has neither a decoded path nor preserved path bytes',
      );
    }

    final List<int> nameCodeUnits = options.mode == CshEncodeMode.permissive && shape.nameCodeUnits.isNotEmpty ? shape.nameCodeUnits : <int>[...shape.name.codeUnits, 0];
    final Uint8List idData = options.mode == CshEncodeMode.permissive && shape.idData.isNotEmpty ? shape.idData : Uint8List.fromList(shape.id.codeUnits);
    final CshVectorPath? path = shape.path;
    final Uint8List pathData = path == null ? shape.pathData : PsVectorPathCodec.encode(path);

    final PsBinaryWriter record = PsBinaryWriter()..writeUint32(nameCodeUnits.length);
    nameCodeUnits.forEach(record.writeUint16);
    if (options.mode == CshEncodeMode.permissive && shape.namePaddingData.isNotEmpty) {
      record.writeBytes(shape.namePaddingData);
    } else {
      record.writeZeros((4 - record.length % 4) % 4);
    }

    final PsBinaryWriter body = PsBinaryWriter()
      ..writeUint8(idData.length)
      ..writeBytes(idData)
      ..writeInt32(shape.bounds.top)
      ..writeInt32(shape.bounds.left)
      ..writeInt32(shape.bounds.bottom)
      ..writeInt32(shape.bounds.right)
      ..writeBytes(pathData);
    if (options.mode == CshEncodeMode.permissive && shape.pathPaddingData.isNotEmpty) {
      body.writeBytes(shape.pathPaddingData);
    } else {
      body.writeZeros((4 - body.length % 4) % 4);
    }
    final Uint8List bodyData = body.takeBytes();
    record
      ..writeUint32(shape.version)
      ..writeUint32(options.mode == CshEncodeMode.strict ? bodyData.length : shape.declaredDataLength)
      ..writeBytes(bodyData);
    return record.takeBytes();
  }

  /// Writes preserved tagged blocks and reconstructs unpreserved hierarchy blocks.
  static void _writeTaggedBlocks(
    PsBinaryWriter writer,
    CshFile file,
    CshEncodeOptions options,
  ) {
    int hierarchyIndex = 0;
    for (final CshTaggedBlock block in file.taggedBlocks) {
      final PsDescriptor? hierarchyDescriptor = block.key == 'phry' && hierarchyIndex < file.hierarchyDescriptors.length ? file.hierarchyDescriptors[hierarchyIndex++] : null;
      final Uint8List data = _taggedBlockData(
        block: block,
        hierarchyDescriptor: hierarchyDescriptor,
        options: options,
      );
      _writeTaggedBlock(writer, block.signature, block.key, data, block.paddingData, options);
    }
    while (hierarchyIndex < file.hierarchyDescriptors.length) {
      final Uint8List data = _encodeHierarchy(file.hierarchyDescriptors[hierarchyIndex++]);
      _writeTaggedBlock(writer, '8BIM', 'phry', data, Uint8List(0), options);
    }
  }

  /// Selects either exact preserved bytes or a regenerated hierarchy descriptor.
  static Uint8List _taggedBlockData({
    required CshTaggedBlock block,
    required PsDescriptor? hierarchyDescriptor,
    required CshEncodeOptions options,
  }) {
    if (options.mode == CshEncodeMode.permissive && block.data.length == block.declaredLength) {
      return block.data;
    }
    if (hierarchyDescriptor != null) {
      return _encodeHierarchy(hierarchyDescriptor);
    }
    if (block.data.length != block.declaredLength) {
      throw CshWriteException(
        message: 'Tagged block ${block.key} has only ${block.data.length} of ${block.declaredLength} payload bytes',
      );
    }
    return block.data;
  }

  /// Encodes one version 16 hierarchy descriptor payload.
  static Uint8List _encodeHierarchy(PsDescriptor descriptor) => PsVersionedDescriptorCodec.encode(
    PsVersionedDescriptor(
      version: _descriptorVersion,
      descriptor: descriptor,
    ),
  );

  /// Writes one ordinary or wide tagged block with requested alignment behavior.
  static void _writeTaggedBlock(
    PsBinaryWriter writer,
    String signature,
    String key,
    Uint8List data,
    Uint8List preservedPadding,
    CshEncodeOptions options,
  ) => PsTaggedBlockCodec.write(
    writer,
    PsTaggedBlock(
      signature: signature,
      key: key,
      data: data,
      paddingData: preservedPadding,
    ),
    preservePadding: options.mode == CshEncodeMode.permissive,
  );

  /// Checks that every emitted field and required payload is representable.
  static void _validateRepresentable(CshFile file, CshEncodeOptions options) {
    _requireLatin1(file.signature, 4, 'CSH signature');
    _requireUnsigned(file.version, 32, 'CSH version');
    _requireUnsigned(file.declaredShapeCount, 32, 'CSH declared shape count');
    if (file.shapes.length > 0xffffffff) {
      throw const CshWriteException(message: 'CSH shape count exceeds the 32-bit container capacity');
    }
    for (final CshShape shape in file.shapes) {
      _requireUnsigned(shape.version, 32, 'Shape ${shape.index + 1} version');
      _requireUnsigned(shape.declaredDataLength, 32, 'Shape ${shape.index + 1} declared body length');
      final List<int> idData = options.mode == CshEncodeMode.permissive && shape.idData.isNotEmpty ? shape.idData : shape.id.codeUnits;
      if (idData.length > 0xff) {
        throw CshWriteException(message: 'Shape ${shape.index + 1} identifier exceeds the 255-byte Pascal-string capacity');
      }
      if (idData.any((value) => value > 0xff)) {
        throw CshWriteException(message: 'Shape ${shape.index + 1} identifier is not Latin-1');
      }
      _requireSigned(shape.bounds.top, 32, 'Shape ${shape.index + 1} top bound');
      _requireSigned(shape.bounds.left, 32, 'Shape ${shape.index + 1} left bound');
      _requireSigned(shape.bounds.bottom, 32, 'Shape ${shape.index + 1} bottom bound');
      _requireSigned(shape.bounds.right, 32, 'Shape ${shape.index + 1} right bound');
      if (shape.path == null && shape.pathData.isEmpty && (options.mode == CshEncodeMode.strict || shape.recordData == null)) {
        throw CshWriteException(message: 'Shape ${shape.index + 1} has no encodable path data');
      }
      if (shape.path == null && shape.pathData.isNotEmpty && shape.pathData.length != shape.pathRecordCount * PsVectorPathCodec.recordByteLength) {
        throw CshWriteException(message: 'Shape ${shape.index + 1} does not retain all declared path-record bytes');
      }
    }
    if (options.includeTaggedBlocks) {
      for (final CshTaggedBlock block in file.taggedBlocks) {
        _requireLatin1(block.signature, 4, 'Tagged-block signature');
        _requireLatin1(block.key, 4, 'Tagged-block key');
        _requireUnsigned(block.declaredLength, block.signature == '8B64' ? 64 : 32, 'Tagged-block ${block.key} declared length');
      }
    }
    if (options.includeTrailingData && file.trailingData.length != file.trailingByteCount) {
      throw CshWriteException(
        message: 'Only ${file.trailingData.length} of ${file.trailingByteCount} trailing bytes were preserved; disable trailing-data output or decode with preservation enabled',
      );
    }
  }

  /// Applies canonical Photoshop constraints to the emitted library.
  static void _validateStrict(CshFile file, CshEncodeOptions options) {
    if (file.signature != _fileSignature || file.version != _fileVersion) {
      throw const CshWriteException(message: 'Strict CSH output requires the "$_fileSignature" signature and version $_fileVersion');
    }
    if (file.declaredShapeCount != file.shapes.length) {
      throw const CshWriteException(message: 'Strict CSH output requires the declared shape count to match the shape list');
    }
    file.shapes.forEach(_validateStrictShape);
    if (options.includeTaggedBlocks) {
      for (final CshTaggedBlock block in file.taggedBlocks) {
        if (block.signature != '8BIM') {
          throw CshWriteException(message: 'Strict CSH output cannot contain tagged-block signature "${block.signature}"');
        }
        if (block.key != 'phry' && block.data.length != block.declaredLength) {
          throw CshWriteException(message: 'Tagged block ${block.key} has no complete preserved payload');
        }
      }
    }
    if (options.includeTrailingData && file.trailingData.isNotEmpty) {
      throw const CshWriteException(message: 'Strict CSH output cannot contain unrecognized trailing bytes');
    }
  }

  /// Validates one canonical version 1 custom-shape record.
  static void _validateStrictShape(CshShape shape) {
    if (shape.version != _shapeVersion) {
      throw CshWriteException(message: 'Shape ${shape.index + 1} must use record version $_shapeVersion');
    }
    if (shape.name.isEmpty || shape.name.codeUnits.contains(0)) {
      throw CshWriteException(message: 'Shape ${shape.index + 1} requires a nonempty name without embedded nulls');
    }
    if (shape.id.isEmpty || shape.id.codeUnits.any((value) => value == 0 || value > 0xff)) {
      throw CshWriteException(message: 'Shape ${shape.index + 1} requires a nonempty Latin-1 identifier without nulls');
    }
    if (!shape.bounds.isValid) {
      throw CshWriteException(message: 'Shape ${shape.index + 1} requires positive reference bounds');
    }
    final CshVectorPath path = shape.path ?? _decodePreservedPath(shape);
    final List<CshPathRecord> records = path.records;
    if (records.length < 2 || records.first is! CshPathFillRuleRecord || records[1] is! CshPathInitialFillRecord) {
      throw CshWriteException(message: 'Shape ${shape.index + 1} path must begin with fill-rule and initial-fill records');
    }
    for (final CshPathRecord record in records) {
      switch (record) {
        case CshSubpathLengthRecord():
          if (record.operation != -1 && CshPathOperation.fromCode(record.operation) == null) {
            throw CshWriteException(message: 'Shape ${shape.index + 1} uses unsupported path operation ${record.operation}');
          }
        case CshBezierKnotRecord():
          final List<CshPathPoint> points = <CshPathPoint>[record.knot.incoming, record.knot.anchor, record.knot.outgoing];
          if (points.any((point) => !point.x.isFinite || !point.y.isFinite || point.x < -16 || point.x >= 16 || point.y < -16 || point.y >= 16)) {
            throw CshWriteException(message: 'Shape ${shape.index + 1} contains a point outside Photoshop\'s documented path range');
          }
        case CshPathFillRuleRecord():
        case CshPathClipboardRecord():
        case CshPathInitialFillRecord():
        case CshUnknownPathRecord():
          if (record is CshUnknownPathRecord) {
            throw CshWriteException(message: 'Shape ${shape.index + 1} contains unknown path selector ${record.selector}');
          }
      }
    }
  }

  /// Decodes retained path bytes so strict validation also covers lazy models.
  static CshVectorPath _decodePreservedPath(CshShape shape) {
    try {
      return PsVectorPathCodec.decode(
        shape.pathData,
        maxRecords: shape.pathRecordCount,
      );
    } on PsFormatException catch (error) {
      throw CshWriteException(
        message: 'Shape ${shape.index + 1} has invalid preserved path data: ${error.message}',
      );
    }
  }

  /// Requires [value] to fit an unsigned integer field.
  static void _requireUnsigned(int value, int bits, String label) {
    final bool exceedsMaximum = bits < 64 && value > (1 << bits) - 1;
    if (value < 0 || exceedsMaximum) {
      throw CshWriteException(message: '$label value $value does not fit an unsigned $bits-bit field');
    }
  }

  /// Requires [value] to fit a signed integer field.
  static void _requireSigned(int value, int bits, String label) {
    final int minimum = -(1 << (bits - 1));
    final int maximum = (1 << (bits - 1)) - 1;
    if (value < minimum || value > maximum) {
      throw CshWriteException(message: '$label value $value does not fit a signed $bits-bit field');
    }
  }

  /// Requires [value] to contain exactly [length] one-byte characters.
  static void _requireLatin1(String value, int length, String label) {
    if (value.length != length || value.codeUnits.any((codeUnit) => codeUnit > 0xff)) {
      throw CshWriteException(message: '$label must contain exactly $length Latin-1 bytes');
    }
  }
}
