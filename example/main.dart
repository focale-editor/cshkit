import 'dart:io';
import 'dart:typed_data';

import 'package:cshkit/cshkit.dart';

/// Reads a CSH library and prints its shapes, hierarchy, and first SVG preview.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/main.dart <library.csh>');
    exitCode = 64;
    return;
  }

  try {
    final Uint8List bytes = await File(arguments.single).readAsBytes();
    final CshFile library = CshDecoder.decode(bytes);
    stdout.writeln(
      '${library.shapes.length}/${library.declaredShapeCount} shapes decoded',
    );
    for (final CshShape shape in library.shapes) {
      final CshVectorPath path = shape.requirePath();
      stdout.writeln(
        '${shape.index + 1}. ${shape.name} [${shape.id}]: '
        '${path.subpaths.length} contours, ${shape.pathRecordCount} records',
      );
    }
    _printHierarchy(library);
    if (library.shapes.isNotEmpty && library.shapes.first.hasValidBounds) {
      stdout.writeln(CshSvgEncoder.document(library.shapes.first));
    }
    library.warnings.forEach(stderr.writeln);
  } on CshFormatException catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln(error);
    exitCode = 66;
  }
}

/// Prints the optional flattened group hierarchy from [library].
void _printHierarchy(CshFile library) {
  for (final CshHierarchyEntry entry in library.hierarchy) {
    final String indentation = '  ' * entry.depth;
    final String label = switch (entry.kind) {
      CshHierarchyEntryKind.groupStart => '+ ${entry.name ?? '<unnamed group>'}',
      CshHierarchyEntryKind.groupEnd => '- <group end>',
      CshHierarchyEntryKind.preset => library.shapeFor(entry)?.name ?? entry.name ?? '<missing shape>',
      CshHierarchyEntryKind.empty => '<empty>',
      CshHierarchyEntryKind.unknown => '<unknown ${entry.classId}>',
    };
    stdout.writeln('$indentation$label');
  }
}
