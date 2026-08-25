import 'dart:typed_data';

import 'package:cshkit/src/codec/csh_hierarchy_mapper.dart';
import 'package:cshkit/src/model/csh_file.dart';
import 'package:cshkit/src/model/csh_hierarchy.dart';
import 'package:cshkit/src/model/csh_options.dart';
import 'package:cshkit/src/model/csh_shape.dart';
import 'package:pscore/pscore.dart';

/// Decodes Adobe Photoshop `cush` custom-shape libraries.
abstract final class CshDecoder {
  /// Four-byte signature used by CSH files and CustomShapes preferences.
  static const String _fileSignature = 'cush';

  /// Four-byte signature used by ordinary Photoshop tagged blocks.
  static const String _taggedBlockSignature = '8BIM';

  /// Alternate signature whose block length occupies eight bytes.
  static const String _largeTaggedBlockSignature = '8B64';

  /// Container version described for custom-shape libraries.
  static const int _fileVersion = 2;

  /// Shape-record version described for custom-shape libraries.
  static const int _shapeVersion = 1;

  /// Descriptor version stored before a Photoshop Action Descriptor.
  static const int _descriptorVersion = 16;

  /// Decodes one complete in-memory CSH [bytes] buffer.
  static CshFile decode(
    Uint8List bytes, {
    CshDecodeOptions options = const CshDecodeOptions(),
  }) {
    _validateOptions(options);
    if (bytes.length > options.maxFileBytes) {
      throw CshFormatException(
        message: 'CSH file size ${bytes.length} exceeds the configured ${options.maxFileBytes} byte limit',
        source: bytes,
        offset: 0,
      );
    }
    try {
      return _decode(bytes, options);
    } on CshFormatException {
      rethrow;
    } on PsFormatException catch (error) {
      throw CshFormatException(
        message: error.message,
        source: bytes,
        offset: error.offset,
      );
    } on RangeError catch (error) {
      throw CshFormatException(
        message: 'Invalid CSH numeric range: $error',
        source: bytes,
      );
    }
  }

  /// Decodes the header, declared shapes, and optional tagged trailer blocks.
  static CshFile _decode(Uint8List bytes, CshDecodeOptions options) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final String signature = reader.readString(4);
    if (signature != _fileSignature) {
      throw CshFormatException(
        message: 'Expected CSH signature "$_fileSignature", found "$signature"',
        source: bytes,
        offset: 0,
      );
    }
    final int version = reader.readUint32();
    final int declaredShapeCount = reader.readUint32();
    if (declaredShapeCount > options.maxShapes) {
      throw CshFormatException(
        message: 'CSH shape count $declaredShapeCount exceeds the configured ${options.maxShapes} limit',
        source: bytes,
        offset: 8,
      );
    }
    final _CshDecodeContext context = _CshDecodeContext(
      bytes: bytes,
      options: options,
      signature: signature,
      version: version,
      declaredShapeCount: declaredShapeCount,
    );
    if (version != _fileVersion) {
      context.issue('CSH container version $version is not currently defined', 4);
    }

    final bool complete = _decodeShapes(reader, context);
    if (complete) {
      _decodeTaggedBlocks(reader, context);
    }
    return context.build();
  }

  /// Decodes every shape declared by the file header.
  static bool _decodeShapes(PsBinaryReader reader, _CshDecodeContext context) {
    for (int index = 0; index < context.declaredShapeCount; index++) {
      context.shapeIndex = index;
      final int recordOffset = reader.offset;
      try {
        final CshShape shape = _decodeShape(
          reader: reader,
          index: index,
          context: context,
        );
        context.addShape(shape);
      } on CshFormatException {
        rethrow;
      } on PsFormatException catch (error) {
        if (_isResourceLimitError(error)) {
          throw CshFormatException(
            message: error.message,
            source: context.bytes,
            offset: error.offset ?? recordOffset,
          );
        }
        if (context.options.mode == CshDecodeMode.strict) {
          rethrow;
        }
        context.warning(
          'Shape ${index + 1} could not be decoded: ${error.message}',
          error.offset ?? recordOffset,
        );
        context.setTrailing(Uint8List.sublistView(context.bytes, recordOffset));
        context.shapeIndex = null;
        return false;
      }
    }
    context.shapeIndex = null;
    return true;
  }

  /// Decodes one length-bounded custom-shape record.
  static CshShape _decodeShape({
    required PsBinaryReader reader,
    required int index,
    required _CshDecodeContext context,
  }) {
    final int recordStart = reader.offset;
    final ({String value, Uint16List codeUnits}) name = _readShapeName(reader, context);
    final int namePaddingLength = (4 - reader.offset % 4) % 4;
    final Uint8List namePaddingData = reader.readBytes(namePaddingLength);
    if (_containsNonzero(namePaddingData)) {
      context.issue('Shape-name alignment padding contains nonzero bytes', reader.offset - namePaddingData.length);
    }

    final int versionOffset = reader.offset;
    final int version = reader.readUint32();
    if (version != _shapeVersion) {
      context.issue('CSH shape-record version $version is not currently defined', versionOffset);
    }
    final int lengthOffset = reader.offset;
    final int declaredDataLength = reader.readUint32();
    if (declaredDataLength > context.options.maxShapeBytes) {
      throw PsFormatException(
        message: 'CSH shape body length $declaredDataLength exceeds the configured ${context.options.maxShapeBytes} byte limit',
        source: context.bytes,
        offset: lengthOffset,
      );
    }
    if (declaredDataLength > reader.remaining) {
      throw PsFormatException(
        message: 'CSH shape body length $declaredDataLength exceeds the ${reader.remaining} remaining bytes',
        source: context.bytes,
        offset: lengthOffset,
      );
    }
    final int bodyOffset = reader.offset;
    final PsBinaryReader body = reader.readReader(declaredDataLength);
    if (body.remaining < 17) {
      throw PsFormatException(
        message: 'CSH shape body is shorter than its identifier and reference rectangle',
        source: context.bytes,
        offset: bodyOffset,
      );
    }

    final int idLengthOffset = body.baseOffset + body.offset;
    final int idLength = body.readUint8();
    if (idLength + 16 > body.remaining) {
      throw PsFormatException(
        message: 'CSH shape identifier length $idLength leaves no complete reference rectangle',
        source: context.bytes,
        offset: idLengthOffset,
      );
    }
    final Uint8List idData = body.readBytes(idLength);
    final String id = _trimTerminalNulls(String.fromCharCodes(idData));
    final CshRectangle bounds = CshRectangle(
      top: body.readInt32(),
      left: body.readInt32(),
      bottom: body.readInt32(),
      right: body.readInt32(),
    );
    if (!bounds.isValid) {
      context.issue('CSH reference bounds ${bounds.width} x ${bounds.height} are not positive', bodyOffset + 1 + idLength);
    }
    if (bounds.width.abs() > context.options.maxDimension || bounds.height.abs() > context.options.maxDimension) {
      throw PsFormatException(
        message: 'CSH reference bounds ${bounds.width} x ${bounds.height} exceed the configured ${context.options.maxDimension} dimension limit',
        source: context.bytes,
        offset: bodyOffset + 1 + idLength,
      );
    }

    final int pathOffset = body.baseOffset + body.offset;
    final int pathPaddingLength = body.remaining % PsVectorPathCodec.recordByteLength;
    final int pathDataLength = body.remaining - pathPaddingLength;
    final int pathRecordCount = pathDataLength ~/ PsVectorPathCodec.recordByteLength;
    context.ensurePathRecords(pathRecordCount, pathOffset);
    final Uint8List pathData = body.readView(pathDataLength);
    final Uint8List pathPaddingData = body.readBytes(pathPaddingLength);
    final CshVectorPath? path = context.options.decodePathData
        ? PsVectorPathCodec.decode(
            pathData,
            maxRecords: pathRecordCount,
          )
        : null;
    if (path != null) {
      _validatePath(
        path: path,
        pathOffset: pathOffset,
        paddingData: pathPaddingData,
        context: context,
      );
    } else {
      _validatePathPadding(
        paddingData: pathPaddingData,
        paddingOffset: pathOffset + pathDataLength,
        context: context,
      );
    }

    final int recordEnd = reader.offset;
    final Uint8List? recordData = context.options.preserveShapeData ? Uint8List.sublistView(context.bytes, recordStart, recordEnd) : null;
    return CshShape(
      index: index,
      sourceOffset: recordStart,
      name: name.value,
      nameCodeUnits: name.codeUnits,
      namePaddingData: namePaddingData,
      version: version,
      declaredDataLength: declaredDataLength,
      id: id,
      idData: idData,
      bounds: bounds,
      path: path,
      pathData: context.options.preservePathData ? pathData : Uint8List(0),
      pathRecordCount: pathRecordCount,
      pathPaddingData: pathPaddingData,
      recordData: recordData,
    );
  }

  /// Reads a length-prefixed big-endian UTF-16 custom-shape name.
  static ({String value, Uint16List codeUnits}) _readShapeName(
    PsBinaryReader reader,
    _CshDecodeContext context,
  ) {
    final int lengthOffset = reader.offset;
    final int length = reader.readUint32();
    if (length > context.options.maxShapeNameCodeUnits) {
      throw PsFormatException(
        message: 'CSH shape-name length $length exceeds the configured ${context.options.maxShapeNameCodeUnits} code-unit limit',
        source: context.bytes,
        offset: lengthOffset,
      );
    }
    if (length > reader.remaining ~/ 2) {
      throw PsFormatException(
        message: 'CSH shape-name length $length exceeds the available data',
        source: context.bytes,
        offset: lengthOffset,
      );
    }
    final Uint16List codeUnits = Uint16List(length);
    for (int index = 0; index < length; index++) {
      codeUnits[index] = reader.readUint16();
    }
    if (codeUnits.isEmpty || codeUnits.last != 0) {
      context.issue('CSH shape name has no terminal null code unit', lengthOffset);
    }
    int end = codeUnits.length;
    while (end > 0 && codeUnits[end - 1] == 0) {
      end--;
    }
    return (
      value: String.fromCharCodes(codeUnits.take(end)),
      codeUnits: codeUnits,
    );
  }

  /// Validates record ordering, contour lengths, operations, and coordinates.
  static void _validatePath({
    required CshVectorPath path,
    required int pathOffset,
    required Uint8List paddingData,
    required _CshDecodeContext context,
  }) {
    final List<CshPathRecord> records = path.records;
    if (records.isEmpty) {
      context.issue('CSH shape contains no path records', pathOffset);
    } else {
      if (records.first is! CshPathFillRuleRecord) {
        context.issue('The first CSH path record is not a fill-rule record', pathOffset);
      }
      if (records.length < 2 || records[1] is! CshPathInitialFillRecord) {
        context.issue('The second CSH path record is not an initial-fill record', pathOffset + PsVectorPathCodec.recordByteLength);
      }
    }

    int index = 0;
    while (index < records.length) {
      final CshPathRecord record = records[index];
      final int recordOffset = pathOffset + index * PsVectorPathCodec.recordByteLength;
      switch (record) {
        case CshSubpathLengthRecord():
          if (record.operation != -1 && CshPathOperation.fromCode(record.operation) == null) {
            context.issue('CSH subpath uses unknown Boolean operation ${record.operation}', recordOffset + 4);
          }
          if (_containsNonzero(Uint8List.sublistView(record.trailingData, 2))) {
            context.issue('CSH subpath-length reserved bytes are not all zero', recordOffset + 8);
          }
          int decodedKnots = 0;
          for (int knotIndex = 0; knotIndex < record.knotCount; knotIndex++) {
            final int candidateIndex = index + 1 + knotIndex;
            if (candidateIndex >= records.length || records[candidateIndex] is! CshBezierKnotRecord) {
              break;
            }
            final CshBezierKnotRecord knotRecord = records[candidateIndex] as CshBezierKnotRecord;
            if (knotRecord.closed != record.closed) {
              context.issue('CSH knot selector disagrees with its subpath openness', pathOffset + candidateIndex * PsVectorPathCodec.recordByteLength);
            }
            _validateKnot(
              knot: knotRecord.knot,
              offset: pathOffset + candidateIndex * PsVectorPathCodec.recordByteLength + 2,
              context: context,
            );
            decodedKnots++;
          }
          if (decodedKnots != record.knotCount) {
            context.issue('CSH subpath declares ${record.knotCount} knots but only $decodedKnots follow', recordOffset + 2);
          }
          index += decodedKnots + 1;
        case CshBezierKnotRecord():
          context.issue('CSH path contains an orphan Bézier-knot record', recordOffset);
          _validateKnot(
            knot: record.knot,
            offset: recordOffset + 2,
            context: context,
          );
          index++;
        case CshPathFillRuleRecord():
          if (record.rule != 0 || _containsNonzero(record.trailingData)) {
            context.issue('CSH path fill-rule payload is not all zero', recordOffset + 2);
          }
          index++;
        case CshPathClipboardRecord():
          if (_containsNonzero(record.trailingData)) {
            context.issue('CSH clipboard reserved bytes are not all zero', recordOffset + 22);
          }
          index++;
        case CshPathInitialFillRecord():
          if (record.rawValue != 0 && record.rawValue != 1) {
            context.issue('CSH initial-fill value ${record.rawValue} is not defined', recordOffset + 2);
          }
          if (_containsNonzero(record.trailingData)) {
            context.issue('CSH initial-fill reserved bytes are not all zero', recordOffset + 4);
          }
          index++;
        case CshUnknownPathRecord():
          context.issue('Unknown CSH path selector ${record.selector} was preserved', recordOffset);
          index++;
      }
    }
    _validatePathPadding(
      paddingData: paddingData,
      paddingOffset: pathOffset + records.length * PsVectorPathCodec.recordByteLength,
      context: context,
    );
  }

  /// Checks one Bézier [knot] against Photoshop's signed path-coordinate range.
  static void _validateKnot({
    required CshBezierKnot knot,
    required int offset,
    required _CshDecodeContext context,
  }) {
    final List<CshPathPoint> points = <CshPathPoint>[
      knot.incoming,
      knot.anchor,
      knot.outgoing,
    ];
    for (int index = 0; index < points.length; index++) {
      final CshPathPoint point = points[index];
      if (point.x < -16 || point.x >= 16 || point.y < -16 || point.y >= 16) {
        context.issue('CSH path point (${point.x}, ${point.y}) exceeds Photoshop\'s documented -16 through 16 range', offset + index * 8);
      }
    }
  }

  /// Validates the short alignment region after complete path records.
  static void _validatePathPadding({
    required Uint8List paddingData,
    required int paddingOffset,
    required _CshDecodeContext context,
  }) {
    if (paddingData.length > 3) {
      context.issue('${paddingData.length} extension bytes remain after the CSH path records', paddingOffset);
    }
    if (_containsNonzero(paddingData)) {
      context.issue('CSH path-record padding contains nonzero bytes', paddingOffset);
    }
  }

  /// Decodes recognizable length-prefixed blocks after the declared shapes.
  static void _decodeTaggedBlocks(PsBinaryReader reader, _CshDecodeContext context) {
    while (!reader.isAtEnd) {
      final int blockOffset = reader.baseOffset + reader.offset;
      if (reader.remaining < 12 || !_hasTaggedSignature(reader, 0)) {
        final Uint8List trailing = reader.readBytes(reader.remaining);
        context.setTrailing(trailing);
        context.issue('${trailing.length} unrecognized trailing bytes remain after the CSH payload', blockOffset);
        return;
      }

      final bool usesWideLength = _hasLargeTaggedSignature(reader);
      if (usesWideLength && reader.remaining < 16) {
        final Uint8List trailing = reader.readBytes(reader.remaining);
        context.setTrailing(trailing);
        context.issue('Truncated CSH 8B64 tagged-block header', blockOffset);
        return;
      }

      final String signature = reader.readString(4);
      final String key = reader.readString(4);
      final int length = usesWideLength ? reader.readUint64() : reader.readUint32();
      final int payloadOffset = blockOffset + (usesWideLength ? 16 : 12);
      context.blockKey = key;
      if (length > context.options.maxTaggedBlockBytes) {
        throw PsFormatException(
          message: 'CSH tagged block $key length $length exceeds the configured ${context.options.maxTaggedBlockBytes} byte limit',
          source: reader.bytes,
          offset: blockOffset + 8,
        );
      }
      if (length > reader.remaining) {
        final Uint8List available = reader.readView(reader.remaining);
        context.addTaggedBlock(
          signature: signature,
          key: key,
          offset: blockOffset,
          declaredLength: length,
          data: available,
          paddingData: Uint8List(0),
        );
        context.issue('CSH tagged block $key length $length exceeds the ${available.length} available bytes', blockOffset + 8);
        context.blockKey = null;
        return;
      }

      final Uint8List payload = reader.readView(length);
      final int paddingLength = _taggedPaddingLength(reader, length);
      final Uint8List padding = reader.readBytes(paddingLength);
      context.addTaggedBlock(
        signature: signature,
        key: key,
        offset: blockOffset,
        declaredLength: length,
        data: payload,
        paddingData: padding,
      );
      if (signature != _taggedBlockSignature) {
        context.issue('CSH tagged block $key uses alternate signature "$signature"', blockOffset);
      }
      if (key == 'phry') {
        _decodeHierarchyBlock(
          payload: payload,
          payloadOffset: payloadOffset,
          context: context,
        );
      } else {
        context.issue('Unknown CSH tagged block $key was preserved', blockOffset + 4);
      }
      context.blockKey = null;
    }
  }

  /// Decodes the versioned Action Descriptor inside a `phry` payload.
  static void _decodeHierarchyBlock({
    required Uint8List payload,
    required int payloadOffset,
    required _CshDecodeContext context,
  }) {
    try {
      final PsBinaryReader descriptorReader = PsBinaryReader(
        bytes: payload,
        baseOffset: payloadOffset,
      );
      final int version = descriptorReader.readUint32();
      if (version != _descriptorVersion) {
        context.issue('CSH hierarchy descriptor version $version is not currently defined', payloadOffset);
      }
      final PsDescriptor descriptor = PsDescriptorCodec.decodeReader(
        descriptorReader,
        options: context.options.descriptorOptions,
      );
      if (!descriptorReader.isAtEnd) {
        context.issue('${descriptorReader.remaining} extension bytes remain after the CSH hierarchy descriptor', descriptorReader.baseOffset + descriptorReader.offset);
      }
      context.addHierarchyDescriptor(descriptor);
      final List<CshHierarchyEntry> entries = CshHierarchyMapper.decode(
        root: descriptor,
        shapes: context.shapes,
        maxEntries: context.options.maxHierarchyEntries,
        onIssue: (message) => context.issue(message, payloadOffset),
      );
      context.addHierarchyEntries(entries);
    } on PsFormatException catch (error) {
      if (_isResourceLimitError(error)) {
        throw CshFormatException(
          message: error.message,
          source: context.bytes,
          offset: error.offset ?? payloadOffset,
        );
      }
      if (context.options.mode == CshDecodeMode.strict) {
        rethrow;
      }
      context.warning(
        'CSH hierarchy could not be decoded: ${error.message}',
        error.offset ?? payloadOffset,
      );
    }
  }

  /// Returns optional zero padding before the next recognizable tagged block.
  static int _taggedPaddingLength(PsBinaryReader reader, int payloadLength) {
    if (_hasTaggedSignature(reader, 0)) {
      return 0;
    }
    final int expectedLength = (4 - payloadLength % 4) % 4;
    if (expectedLength == 0 || reader.remaining < expectedLength || !_allZero(reader, expectedLength)) {
      return 0;
    }
    if (reader.remaining == expectedLength || _hasTaggedSignature(reader, expectedLength)) {
      return expectedLength;
    }
    return 0;
  }

  /// Tests whether the first [length] remaining bytes are all zero.
  static bool _allZero(PsBinaryReader reader, int length) {
    for (int index = 0; index < length; index++) {
      if (reader.bytes[reader.offset + index] != 0) {
        return false;
      }
    }
    return true;
  }

  /// Tests whether a supported tagged signature starts at [relativeOffset].
  static bool _hasTaggedSignature(PsBinaryReader reader, int relativeOffset) {
    if (relativeOffset < 0 || reader.remaining < relativeOffset + 4) {
      return false;
    }
    final int offset = reader.offset + relativeOffset;
    final String signature = String.fromCharCodes(Uint8List.sublistView(reader.bytes, offset, offset + 4));
    return signature == _taggedBlockSignature || signature == _largeTaggedBlockSignature;
  }

  /// Tests whether the current tagged block uses a 64-bit payload length.
  static bool _hasLargeTaggedSignature(PsBinaryReader reader) {
    if (reader.remaining < 4) {
      return false;
    }
    final int offset = reader.offset;
    return String.fromCharCodes(Uint8List.sublistView(reader.bytes, offset, offset + 4)) == _largeTaggedBlockSignature;
  }

  /// Tests whether [bytes] contains at least one nonzero value.
  static bool _containsNonzero(Uint8List bytes) {
    for (final int value in bytes) {
      if (value != 0) {
        return true;
      }
    }
    return false;
  }

  /// Whether [error] represents a configured safety limit rather than damage.
  static bool _isResourceLimitError(PsFormatException error) => error.message.contains('configured');

  /// Removes only terminal null characters from [value].
  static String _trimTerminalNulls(String value) {
    int end = value.length;
    while (end > 0 && value.codeUnitAt(end - 1) == 0) {
      end--;
    }
    return value.substring(0, end);
  }

  /// Rejects negative resource limits before any input is processed.
  static void _validateOptions(CshDecodeOptions options) {
    final List<({String name, int value})> limits = <({String name, int value})>[
      (name: 'maxFileBytes', value: options.maxFileBytes),
      (name: 'maxShapes', value: options.maxShapes),
      (name: 'maxDimension', value: options.maxDimension),
      (name: 'maxShapeNameCodeUnits', value: options.maxShapeNameCodeUnits),
      (name: 'maxShapeBytes', value: options.maxShapeBytes),
      (name: 'maxPathRecords', value: options.maxPathRecords),
      (name: 'maxTaggedBlockBytes', value: options.maxTaggedBlockBytes),
      (name: 'maxHierarchyEntries', value: options.maxHierarchyEntries),
      (
        name: 'descriptorOptions.maxDepth',
        value: options.descriptorOptions.maxDepth,
      ),
      (
        name: 'descriptorOptions.maxValues',
        value: options.descriptorOptions.maxValues,
      ),
    ];
    for (final ({String name, int value}) limit in limits) {
      if (limit.value < 0) {
        throw ArgumentError.value(limit.value, limit.name, 'must not be negative');
      }
    }
  }
}

/// Mutable state shared by bounded CSH decoding stages.
final class _CshDecodeContext {
  /// Complete source bytes used for preserved slices and error context.
  final Uint8List bytes;

  /// Resource, strictness, and preservation options.
  final CshDecodeOptions options;

  /// Four-byte container signature.
  final String signature;

  /// Container version from the file header.
  final int version;

  /// Shape count declared by the file header.
  final int declaredShapeCount;

  /// Successfully decoded shapes.
  final List<CshShape> shapes = <CshShape>[];

  /// Flattened typed hierarchy entries.
  final List<CshHierarchyEntry> hierarchy = <CshHierarchyEntry>[];

  /// Decoded source hierarchy descriptors.
  final List<PsDescriptor> hierarchyDescriptors = <PsDescriptor>[];

  /// Preserved tagged trailer blocks.
  final List<CshTaggedBlock> taggedBlocks = <CshTaggedBlock>[];

  /// Recoverable compatibility issues.
  final List<CshWarning> warnings = <CshWarning>[];

  /// Last decoded shape for every nonempty identifier.
  final Map<String, CshShape> _shapesById = <String, CshShape>{};

  /// Aggregate number of accepted path records.
  int _pathRecords = 0;

  /// Current shape index used to annotate warnings.
  int? shapeIndex;

  /// Current tagged-block key used to annotate warnings.
  String? blockKey;

  /// Preserved bytes not recognized as shapes or tagged blocks.
  Uint8List trailingData = Uint8List(0);

  /// Number of unrecognized trailing bytes whether or not they are preserved.
  int trailingByteCount = 0;

  /// Creates decode state for one CSH buffer.
  _CshDecodeContext({
    required this.bytes,
    required this.options,
    required this.signature,
    required this.version,
    required this.declaredShapeCount,
  });

  /// Reports a recoverable issue or throws it under strict decoding.
  void issue(String message, int offset) {
    if (options.mode == CshDecodeMode.strict) {
      throw CshFormatException(
        message: message,
        source: bytes,
        offset: offset,
      );
    }
    warning(message, offset);
  }

  /// Adds a warning independently of strict compatibility handling.
  void warning(String message, int offset) {
    warnings.add(
      CshWarning(
        message: message,
        offset: offset,
        shapeIndex: shapeIndex,
        blockKey: blockKey,
      ),
    );
  }

  /// Verifies that [additional] records fit the aggregate configured budget.
  void ensurePathRecords(int additional, int offset) {
    if (_pathRecords + additional > options.maxPathRecords) {
      throw PsFormatException(
        message: 'CSH path record count exceeds the configured ${options.maxPathRecords} limit',
        source: bytes,
        offset: offset,
      );
    }
    _pathRecords += additional;
  }

  /// Preserves one decoded [shape] and reports duplicate identifiers.
  void addShape(CshShape shape) {
    if (shape.id.isEmpty) {
      issue('CSH shape has an empty identifier', shape.sourceOffset);
    } else if (_shapesById.containsKey(shape.id)) {
      issue('CSH shape identifier "${shape.id}" is duplicated', shape.sourceOffset);
    }
    shapes.add(shape);
    if (shape.id.isNotEmpty) {
      _shapesById[shape.id] = shape;
    }
  }

  /// Preserves one tagged block according to the configured payload policy.
  void addTaggedBlock({
    required String signature,
    required String key,
    required int offset,
    required int declaredLength,
    required Uint8List data,
    required Uint8List paddingData,
  }) {
    taggedBlocks.add(
      CshTaggedBlock(
        signature: signature,
        key: key,
        offset: offset,
        declaredLength: declaredLength,
        data: options.preserveTaggedBlockData ? data : Uint8List(0),
        paddingData: paddingData,
      ),
    );
  }

  /// Preserves one successfully decoded hierarchy descriptor.
  void addHierarchyDescriptor(PsDescriptor descriptor) {
    hierarchyDescriptors.add(descriptor);
  }

  /// Adds decoded hierarchy [entries] after rebasing their source indices.
  void addHierarchyEntries(List<CshHierarchyEntry> entries) {
    final int indexOffset = hierarchy.length;
    hierarchy.addAll(<CshHierarchyEntry>[
      for (final CshHierarchyEntry entry in entries)
        CshHierarchyEntry(
          index: entry.index + indexOffset,
          kind: entry.kind,
          depth: entry.depth,
          classId: entry.classId,
          name: entry.name,
          id: entry.id,
          shapeIndex: entry.shapeIndex,
          rawDescriptor: entry.rawDescriptor,
        ),
    ]);
  }

  /// Records unrecognized [bytes] according to the preservation policy.
  void setTrailing(Uint8List bytes) {
    trailingByteCount = bytes.length;
    trailingData = options.preserveTrailingData ? Uint8List.fromList(bytes) : Uint8List(0);
  }

  /// Builds the immutable public result.
  CshFile build() => CshFile(
    signature: signature,
    version: version,
    declaredShapeCount: declaredShapeCount,
    shapes: shapes,
    hierarchy: hierarchy,
    hierarchyDescriptors: hierarchyDescriptors,
    taggedBlocks: taggedBlocks,
    trailingData: trailingData,
    trailingByteCount: trailingByteCount,
    warnings: warnings,
  );
}
