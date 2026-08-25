import 'package:cshkit/src/model/csh_shape.dart';

/// Selects the coordinate system used by SVG geometry helpers.
enum CshSvgCoordinateSpace {
  /// Keeps Photoshop's normalized path coordinates.
  normalized,

  /// Scales coordinates into a zero-based rectangle of the shape's size.
  local,

  /// Scales and offsets coordinates into the stored reference rectangle.
  reference,
}

/// Converts decoded custom-shape geometry to dependency-free SVG text.
abstract final class CshSvgEncoder {
  /// Returns SVG path commands for all decoded contours in [shape].
  ///
  /// Photoshop Boolean operations remain available on each `CshSubpath`; SVG
  /// path text alone does not encode their combine, subtract, or intersect
  /// semantics.
  static String pathData(
    CshShape shape, {
    CshSvgCoordinateSpace coordinateSpace = CshSvgCoordinateSpace.local,
    int fractionDigits = 6,
  }) {
    _validateFractionDigits(fractionDigits);
    final List<CshSubpath> subpaths = switch (coordinateSpace) {
      CshSvgCoordinateSpace.normalized => shape.requirePath().subpaths,
      CshSvgCoordinateSpace.local => shape.localSubpaths(),
      CshSvgCoordinateSpace.reference => shape.referenceSubpaths(),
    };
    final StringBuffer output = StringBuffer();
    for (final CshSubpath subpath in subpaths) {
      if (subpath.knots.isEmpty) {
        continue;
      }
      if (output.isNotEmpty) {
        output.write(' ');
      }
      final CshBezierKnot first = subpath.knots.first;
      output.write('M${_point(first.anchor, fractionDigits)}');
      for (int index = 1; index < subpath.knots.length; index++) {
        final CshBezierKnot previous = subpath.knots[index - 1];
        final CshBezierKnot current = subpath.knots[index];
        _writeCurve(
          output: output,
          outgoing: previous.outgoing,
          incoming: current.incoming,
          anchor: current.anchor,
          fractionDigits: fractionDigits,
        );
      }
      if (subpath.closed) {
        final CshBezierKnot last = subpath.knots.last;
        _writeCurve(
          output: output,
          outgoing: last.outgoing,
          incoming: first.incoming,
          anchor: first.anchor,
          fractionDigits: fractionDigits,
        );
        output.write('Z');
      }
    }
    return output.toString();
  }

  /// Returns a standalone SVG document suitable for previews and diagnostics.
  ///
  /// The even-odd fill is a portable preview convention; callers that need
  /// Photoshop-exact Boolean composition should consume the typed subpaths.
  static String document(
    CshShape shape, {
    CshSvgCoordinateSpace coordinateSpace = CshSvgCoordinateSpace.local,
    int fractionDigits = 6,
    String fill = 'black',
  }) {
    if (!shape.hasValidBounds) {
      throw StateError('Cannot create an SVG view box from invalid bounds ${shape.width} x ${shape.height}');
    }
    _validateFractionDigits(fractionDigits);
    final ({double left, double top, double width, double height}) viewBox = switch (coordinateSpace) {
      CshSvgCoordinateSpace.normalized => (left: 0, top: 0, width: 1, height: 1),
      CshSvgCoordinateSpace.local => (left: 0, top: 0, width: shape.width.toDouble(), height: shape.height.toDouble()),
      CshSvgCoordinateSpace.reference => (
        left: shape.bounds.left.toDouble(),
        top: shape.bounds.top.toDouble(),
        width: shape.width.toDouble(),
        height: shape.height.toDouble(),
      ),
    };
    final String path = pathData(
      shape,
      coordinateSpace: coordinateSpace,
      fractionDigits: fractionDigits,
    );
    final String encodedViewBox = <double>[viewBox.left, viewBox.top, viewBox.width, viewBox.height].map((value) => _number(value, fractionDigits)).join(' ');
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$encodedViewBox"><path d="${_escapeAttribute(path)}" fill="${_escapeAttribute(fill)}" fill-rule="evenodd"/></svg>';
  }

  /// Writes one cubic segment from two handles and its destination [anchor].
  static void _writeCurve({
    required StringBuffer output,
    required CshPathPoint outgoing,
    required CshPathPoint incoming,
    required CshPathPoint anchor,
    required int fractionDigits,
  }) {
    output
      ..write('C${_point(outgoing, fractionDigits)} ')
      ..write('${_point(incoming, fractionDigits)} ')
      ..write(_point(anchor, fractionDigits));
  }

  /// Formats one SVG point as comma-separated horizontal and vertical values.
  static String _point(CshPathPoint point, int fractionDigits) => '${_number(point.x, fractionDigits)},${_number(point.y, fractionDigits)}';

  /// Formats a finite number without insignificant terminal zeroes.
  static String _number(double value, int fractionDigits) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'SVG coordinates must be finite');
    }
    final double normalized = value == 0 ? 0 : value;
    final String fixed = normalized.toStringAsFixed(fractionDigits);
    if (!fixed.contains('.')) {
      return fixed;
    }
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// Escapes text for use inside a quoted XML attribute.
  static String _escapeAttribute(String value) => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// Ensures [fractionDigits] is accepted by `double.toStringAsFixed`.
  static void _validateFractionDigits(int fractionDigits) {
    if (fractionDigits < 0 || fractionDigits > 20) {
      throw RangeError.range(fractionDigits, 0, 20, 'fractionDigits');
    }
  }
}
