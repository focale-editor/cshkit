import 'dart:typed_data';

import 'package:pscore/pscore.dart';

/// Signed reference rectangle stored by a custom-shape record.
typedef CshRectangle = PsRectangle;

/// Boolean operation applied when Photoshop combines a shape contour.
typedef CshPathOperation = PsPathOperation;

/// Fill rule inferred from a shape contour's flags.
typedef CshPathFillRule = PsPathFillRule;

/// A point in normalized or transformed custom-shape coordinates.
typedef CshPathPoint = PsPathPoint;

/// One cubic Bézier knot in a custom shape.
typedef CshBezierKnot = PsBezierKnot;

/// One open or closed custom-shape contour.
typedef CshSubpath = PsSubpath;

/// Base type for one fixed-size custom-shape path record.
typedef CshPathRecord = PsPathRecord;

/// A record declaring the knot count and operation of a contour.
typedef CshSubpathLengthRecord = PsSubpathLengthRecord;

/// A record containing one cubic Bézier knot.
typedef CshBezierKnotRecord = PsBezierKnotRecord;

/// A custom-shape path fill-rule record.
typedef CshPathFillRuleRecord = PsPathFillRuleRecord;

/// A custom-shape clipboard record.
typedef CshPathClipboardRecord = PsPathClipboardRecord;

/// A custom-shape initial-fill record.
typedef CshPathInitialFillRecord = PsPathInitialFillRecord;

/// An unrecognized custom-shape path record.
typedef CshUnknownPathRecord = PsUnknownPathRecord;

/// An ordered custom-shape path retaining every decoded source record.
typedef CshVectorPath = PsVectorPath;

/// One complete vector preset from a Photoshop custom-shape library.
final class CshShape {
  /// Zero-based position in the source library.
  final int index;

  /// Absolute byte offset of the shape-name length field.
  final int sourceOffset;

  /// User-visible name with terminal null code units removed.
  final String name;

  /// Exact UTF-16 code units, including any terminal nulls.
  final Uint16List nameCodeUnits;

  /// Alignment bytes following the encoded name.
  final Uint8List namePaddingData;

  /// Shape-record version, normally 1.
  final int version;

  /// Body length exactly as declared by the shape header.
  final int declaredDataLength;

  /// Pascal identifier decoded as Latin-1 with terminal null bytes removed.
  final String id;

  /// Exact Pascal identifier payload without its length byte.
  final Uint8List idData;

  /// Signed reference rectangle used to scale normalized path coordinates.
  final CshRectangle bounds;

  /// Decoded vector path, or `null` when path decoding was disabled.
  final CshVectorPath? path;

  /// Exact path-record bytes, or an empty list when preservation was disabled.
  final Uint8List pathData;

  /// Number of complete 26-byte path records in the shape body.
  final int pathRecordCount;

  /// Bytes after the last complete path record inside the shape body.
  final Uint8List pathPaddingData;

  /// Complete source record, or `null` when preservation was disabled.
  final Uint8List? recordData;

  /// Creates an immutable decoded custom shape.
  CshShape({
    required this.index,
    required this.sourceOffset,
    required this.name,
    required Uint16List nameCodeUnits,
    required Uint8List namePaddingData,
    required this.version,
    required this.declaredDataLength,
    required this.id,
    required Uint8List idData,
    required this.bounds,
    required this.path,
    required Uint8List pathData,
    required this.pathRecordCount,
    required Uint8List pathPaddingData,
    required Uint8List? recordData,
  }) : nameCodeUnits = Uint16List.fromList(nameCodeUnits).asUnmodifiableView(),
       namePaddingData = Uint8List.fromList(namePaddingData).asUnmodifiableView(),
       idData = Uint8List.fromList(idData).asUnmodifiableView(),
       pathData = Uint8List.fromList(pathData).asUnmodifiableView(),
       pathPaddingData = Uint8List.fromList(pathPaddingData).asUnmodifiableView(),
       recordData = recordData == null ? null : Uint8List.fromList(recordData).asUnmodifiableView();

  /// Width of the reference rectangle.
  int get width => bounds.width;

  /// Height of the reference rectangle.
  int get height => bounds.height;

  /// Whether [bounds] has positive width and height.
  bool get hasValidBounds => bounds.isValid;

  /// Whether [path] was decoded and can be traversed.
  bool get hasDecodedPath => path != null;

  /// Returns the decoded path or throws when decoding was disabled.
  CshVectorPath requirePath() {
    final CshVectorPath? decodedPath = path;
    if (decodedPath == null) {
      throw StateError('Path data was not decoded for shape "$name"');
    }
    return decodedPath;
  }

  /// Converts a normalized [point] to shape-local reference pixels.
  CshPathPoint localPoint(CshPathPoint point) => point.transform(
    scaleX: width.toDouble(),
    scaleY: height.toDouble(),
  );

  /// Converts a normalized [point] to absolute reference coordinates.
  CshPathPoint referencePoint(CshPathPoint point) => point.transform(
    scaleX: width.toDouble(),
    scaleY: height.toDouble(),
    translateX: bounds.left.toDouble(),
    translateY: bounds.top.toDouble(),
  );

  /// Returns decoded contours in shape-local reference pixels.
  List<CshSubpath> localSubpaths() => _transformSubpaths(
    scaleX: width.toDouble(),
    scaleY: height.toDouble(),
  );

  /// Returns decoded contours in absolute reference coordinates.
  List<CshSubpath> referenceSubpaths() => _transformSubpaths(
    scaleX: width.toDouble(),
    scaleY: height.toDouble(),
    translateX: bounds.left.toDouble(),
    translateY: bounds.top.toDouble(),
  );

  /// Transforms every semantic contour while retaining operations and flags.
  List<CshSubpath> _transformSubpaths({
    required double scaleX,
    required double scaleY,
    double translateX = 0,
    double translateY = 0,
  }) => List<CshSubpath>.unmodifiable(<CshSubpath>[
    for (final CshSubpath subpath in requirePath().subpaths)
      subpath.transform(
        scaleX: scaleX,
        scaleY: scaleY,
        translateX: translateX,
        translateY: translateY,
      ),
  ]);
}
