import 'dart:io';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:cshkit/cshkit.dart';
import 'package:test/test.dart';

/// Validates locally supplied Photoshop CSH examples when a corpus is present.
void main() {
  final List<File> examples = _examples();
  test(
    'strictly decodes and losslessly reconstructs every local Photoshop example',
    () {
      for (final File example in examples) {
        final Uint8List source = example.readAsBytesSync();
        final CshFile decoded = CshDecoder.decode(
          source,
          options: const CshDecodeOptions(mode: CshDecodeMode.strict),
        );
        final Uint8List reconstructed = CshEncoder.encode(decoded);

        check(decoded.shapes).isNotEmpty();
        check(reconstructed, because: example.path).deepEquals(source);
      }
    },
    skip: examples.isEmpty ? 'No local CSH_EXAMPLES or CSH EXAMPLES corpus is present.' : false,
  );
}

/// Discovers case-insensitive `.csh` files in conventional local corpus folders.
List<File> _examples() {
  final List<File> files = <File>[];
  for (final String path in const <String>['CSH_EXAMPLES', 'CSH EXAMPLES']) {
    final Directory directory = Directory(path);
    if (directory.existsSync()) {
      files.addAll(
        directory.listSync(recursive: true).whereType<File>().where((file) => file.path.toLowerCase().endsWith('.csh')),
      );
    }
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}
