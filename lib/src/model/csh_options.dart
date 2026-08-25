import 'package:pscore/pscore.dart';

/// Controls whether recoverable CSH compatibility issues stop decoding.
enum CshDecodeMode {
  /// Rejects unknown extensions and malformed optional data.
  strict,

  /// Preserves unknown data and reports recoverable defects as warnings.
  tolerant,
}

/// Resource and preservation limits applied while decoding a CSH library.
final class CshDecodeOptions {
  /// Handling policy for recoverable format extensions and damaged records.
  final CshDecodeMode mode;

  /// Maximum accepted input size.
  final int maxFileBytes;

  /// Maximum number of custom shapes declared by one library.
  final int maxShapes;

  /// Maximum absolute width or height accepted for a reference rectangle.
  final int maxDimension;

  /// Maximum UTF-16 code-unit count accepted for one shape name.
  final int maxShapeNameCodeUnits;

  /// Maximum byte length accepted for one shape body.
  final int maxShapeBytes;

  /// Maximum aggregate number of 26-byte path records.
  final int maxPathRecords;

  /// Maximum payload length accepted for one trailing tagged block.
  final int maxTaggedBlockBytes;

  /// Maximum number of hierarchy entries exposed from `phry` descriptors.
  final int maxHierarchyEntries;

  /// Resource limits applied to every hierarchy Action Descriptor.
  final PsDescriptorDecodeOptions descriptorOptions;

  /// Whether fixed-size path records are decoded into vector geometry.
  final bool decodePathData;

  /// Whether each shape retains its exact encoded path-record bytes.
  final bool preservePathData;

  /// Whether each shape retains a complete copy of its source record.
  final bool preserveShapeData;

  /// Whether tagged trailer blocks retain their complete payload bytes.
  final bool preserveTaggedBlockData;

  /// Whether bytes not recognized as shapes or tagged blocks are retained.
  final bool preserveTrailingData;

  /// Creates bounded decode options suitable for untrusted input.
  const CshDecodeOptions({
    this.mode = CshDecodeMode.tolerant,
    this.maxFileBytes = 512 * 1024 * 1024,
    this.maxShapes = 100000,
    this.maxDimension = 10000000,
    this.maxShapeNameCodeUnits = 1024 * 1024,
    this.maxShapeBytes = 256 * 1024 * 1024,
    this.maxPathRecords = 2000000,
    this.maxTaggedBlockBytes = 64 * 1024 * 1024,
    this.maxHierarchyEntries = 100000,
    this.descriptorOptions = const PsDescriptorDecodeOptions(),
    this.decodePathData = true,
    this.preservePathData = true,
    this.preserveShapeData = true,
    this.preserveTaggedBlockData = true,
    this.preserveTrailingData = true,
  });
}

/// Describes a recoverable compatibility issue found while decoding.
final class CshWarning {
  /// Human-readable explanation of the compatibility issue.
  final String message;

  /// Absolute byte offset associated with the issue, when known.
  final int? offset;

  /// Zero-based shape index associated with the issue, when known.
  final int? shapeIndex;

  /// Tagged-block key associated with the issue, when known.
  final String? blockKey;

  /// Creates a warning with optional source context.
  const CshWarning({
    required this.message,
    this.offset,
    this.shapeIndex,
    this.blockKey,
  });

  @override
  String toString() {
    final String location = offset == null ? '' : ' at byte $offset';
    final int? currentShapeIndex = shapeIndex;
    final String shape = currentShapeIndex == null ? '' : ' in shape ${currentShapeIndex + 1}';
    final String block = blockKey == null ? '' : ' in $blockKey';
    return 'CshWarning$location$shape$block: $message';
  }
}

/// Reports malformed, truncated, unsupported, or unsafe CSH input.
final class CshFormatException implements FormatException {
  /// Human-readable explanation of the malformed data.
  @override
  final String message;

  /// Input associated with the failure, when useful.
  @override
  final Object? source;

  /// Absolute byte offset associated with the failure, when known.
  @override
  final int? offset;

  /// Creates a CSH format error at an optional absolute byte [offset].
  const CshFormatException({
    required this.message,
    this.source,
    this.offset,
  });

  @override
  String toString() {
    final String location = offset == null ? '' : ' at byte $offset';
    return 'CshFormatException$location: $message';
  }
}
