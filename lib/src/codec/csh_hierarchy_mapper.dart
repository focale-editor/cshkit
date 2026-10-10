import 'package:cshkit/src/model/csh_hierarchy.dart';
import 'package:cshkit/src/model/csh_shape.dart';
import 'package:pscore/pscore.dart';

/// Receives a recoverable hierarchy compatibility issue.
typedef CshHierarchyIssueHandler = PsPresetHierarchyIssueHandler;

/// Adapts the shared Photoshop hierarchy mapper to CSH shape entries.
abstract final class CshHierarchyMapper {
  /// Decodes the ordered list stored under the root `hierarchy` key.
  static List<CshHierarchyEntry> decode({
    required PsDescriptor root,
    required List<CshShape> shapes,
    required int maxEntries,
    required CshHierarchyIssueHandler onIssue,
  }) => List<CshHierarchyEntry>.unmodifiable(<CshHierarchyEntry>[
    for (final PsPresetHierarchyEntry entry in PsPresetHierarchyMapper.decode(
      root: root,
      presets: <PsPresetIdentity>[
        for (final CshShape shape in shapes)
          PsPresetIdentity(
            name: shape.name,
            id: shape.id,
          ),
      ],
      maxEntries: maxEntries,
      onIssue: onIssue,
      formatLabel: 'CSH',
      presetLabel: 'a decoded shape',
    ))
      CshHierarchyEntry(
        index: entry.index,
        kind: entry.kind,
        depth: entry.depth,
        classId: entry.classId,
        name: entry.name,
        id: entry.id,
        shapeIndex: entry.presetIndex,
        rawDescriptor: entry.rawDescriptor,
      ),
  ]);
}
