import 'dart:io';
import 'dart:typed_data';

import 'package:cshkit/cshkit.dart';

/// Inspects CSH libraries and reports their decoded structural coverage.
void main(List<String> arguments) {
  final bool metadataOnly = arguments.contains('--metadata-only');
  final bool summaryOnly = arguments.contains('--summary-only');
  final bool strict = arguments.contains('--strict');
  final List<String> paths = <String>[
    for (final String argument in arguments)
      if (!argument.startsWith('--')) argument,
  ];
  if (paths.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/inspect_csh.dart '
      '[--metadata-only] [--summary-only] [--strict] '
      '<file-or-directory> [...]',
    );
    exitCode = 64;
    return;
  }

  final List<File> files = _cshFiles(paths);
  if (files.isEmpty) {
    stderr.writeln('No CSH or CustomShapes.psp files found.');
    exitCode = 66;
    return;
  }
  for (final File file in files) {
    _inspect(
      file,
      metadataOnly: metadataOnly,
      summaryOnly: summaryOnly,
      strict: strict,
    );
  }
}

/// Returns supported custom-shape files contained in the requested [paths].
List<File> _cshFiles(List<String> paths) {
  final List<File> files = <File>[];
  for (final String path in paths) {
    switch (FileSystemEntity.typeSync(path)) {
      case FileSystemEntityType.file:
        if (_isCshPath(path)) {
          files.add(File(path));
        }
      case FileSystemEntityType.directory:
        files.addAll(
          Directory(path).listSync(recursive: true).whereType<File>().where((file) => _isCshPath(file.path)),
        );
      case FileSystemEntityType.link:
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        break;
    }
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

/// Decodes and prints one concise report for [file].
void _inspect(
  File file, {
  required bool metadataOnly,
  required bool summaryOnly,
  required bool strict,
}) {
  try {
    final Uint8List bytes = file.readAsBytesSync();
    final CshFile decoded = CshDecoder.decode(
      bytes,
      options: CshDecodeOptions(
        mode: strict ? CshDecodeMode.strict : CshDecodeMode.tolerant,
        decodePathData: !metadataOnly,
        preservePathData: false,
        preserveShapeData: false,
        preserveTaggedBlockData: false,
        preserveTrailingData: false,
      ),
    );
    stdout.writeln(
      '${file.path}: ${decoded.shapes.length}/${decoded.declaredShapeCount} shapes, '
      '${decoded.taggedBlocks.length} tagged blocks, ${decoded.hierarchy.length} hierarchy entries, '
      '${decoded.trailingByteCount} trailing bytes, ${decoded.warnings.length} warnings',
    );
    if (!summaryOnly) {
      for (final CshShape shape in decoded.shapes) {
        final CshVectorPath? path = shape.path;
        final List<CshSubpath> subpaths = path?.subpaths ?? const <CshSubpath>[];
        final int knotCount = subpaths.fold<int>(0, (sum, subpath) => sum + subpath.knots.length);
        final Set<int> operations = <int>{for (final CshSubpath subpath in subpaths) subpath.operation};
        stdout.writeln(
          '  ${shape.index + 1}. ${shape.name} [${shape.id}] bounds '
          '${shape.bounds.left},${shape.bounds.top} ${shape.width}x${shape.height}, '
          '${shape.pathRecordCount} records, ${subpaths.length} subpaths, $knotCount knots, operations $operations',
        );
      }
      for (final CshHierarchyEntry entry in decoded.hierarchy) {
        final String indentation = '  ' * (entry.depth + 1);
        final String label = switch (entry.kind) {
          CshHierarchyEntryKind.groupStart => '+ ${entry.name ?? '<unnamed group>'}',
          CshHierarchyEntryKind.groupEnd => '- <group end>',
          CshHierarchyEntryKind.preset => decoded.shapeFor(entry)?.name ?? entry.name ?? '<missing preset>',
          CshHierarchyEntryKind.empty => '<empty>',
          CshHierarchyEntryKind.unknown => '<unknown ${entry.classId}>',
        };
        stdout.writeln('$indentation$label');
      }
    }
    for (final CshWarning warning in decoded.warnings) {
      stdout.writeln('  warning: $warning');
    }
  } on Object catch (error) {
    stderr.writeln('${file.path}: $error');
    exitCode = 1;
  }
}

/// Whether [path] names a CSH library or Photoshop custom-shape preferences.
bool _isCshPath(String path) {
  final String normalized = path.toLowerCase().replaceAll('\\', '/');
  return normalized.endsWith('.csh') || normalized.endsWith('/customshapes.psp');
}
