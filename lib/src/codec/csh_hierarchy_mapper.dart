import 'package:cshkit/src/model/csh_hierarchy.dart';
import 'package:cshkit/src/model/csh_shape.dart';
import 'package:pscore/pscore.dart';

/// Receives a recoverable hierarchy compatibility issue.
typedef CshHierarchyIssueHandler = void Function(String message);

/// Converts a generic Photoshop hierarchy descriptor into typed CSH entries.
abstract final class CshHierarchyMapper {
  /// Decodes the ordered list stored under the root `hierarchy` key.
  static List<CshHierarchyEntry> decode({
    required PsDescriptor root,
    required List<CshShape> shapes,
    required int maxEntries,
    required CshHierarchyIssueHandler onIssue,
  }) {
    final PsDescriptorValue? hierarchyValue = root.value('hierarchy');
    if (hierarchyValue == null) {
      onIssue('The phry descriptor has no hierarchy item');
      return const <CshHierarchyEntry>[];
    }
    if (hierarchyValue is! PsListValue) {
      onIssue('The phry hierarchy item is ${hierarchyValue.type}, not a list');
      return const <CshHierarchyEntry>[];
    }
    if (hierarchyValue.values.length > maxEntries) {
      throw PsFormatException(message: 'CSH hierarchy entry count ${hierarchyValue.values.length} exceeds the configured $maxEntries limit');
    }

    final List<CshHierarchyEntry> entries = <CshHierarchyEntry>[];
    int depth = 0;
    int nextShapeIndex = 0;
    for (int index = 0; index < hierarchyValue.values.length; index++) {
      final PsDescriptorValue value = hierarchyValue.values[index];
      final PsDescriptor? descriptor = switch (value) {
        PsObjectValue(:final PsDescriptor value) => value,
        _ => null,
      };
      if (descriptor == null) {
        entries.add(
          CshHierarchyEntry(
            index: index,
            kind: CshHierarchyEntryKind.empty,
            depth: depth,
            classId: null,
            name: null,
            id: null,
            shapeIndex: null,
            rawDescriptor: null,
          ),
        );
        if (value is! PsRawValue || value.value.isNotEmpty) {
          onIssue('Hierarchy entry ${index + 1} uses unsupported value type ${value.type}');
        }
        continue;
      }

      final String classId = descriptor.classId;
      final String? name = _firstString(descriptor, const <String>['Nm  ', 'name']);
      final String? id = _firstString(descriptor, const <String>['zuid', 'Idnt', 'identifier']);
      switch (classId) {
        case 'Grup':
        case 'group':
        case 'groupStart':
          entries.add(
            CshHierarchyEntry(
              index: index,
              kind: CshHierarchyEntryKind.groupStart,
              depth: depth,
              classId: classId,
              name: name,
              id: id,
              shapeIndex: null,
              rawDescriptor: descriptor,
            ),
          );
          depth++;
        case 'groupEnd':
          if (depth == 0) {
            onIssue('Hierarchy entry ${index + 1} closes a group that was not open');
          } else {
            depth--;
          }
          entries.add(
            CshHierarchyEntry(
              index: index,
              kind: CshHierarchyEntryKind.groupEnd,
              depth: depth,
              classId: classId,
              name: name,
              id: id,
              shapeIndex: null,
              rawDescriptor: descriptor,
            ),
          );
        case 'preset':
          final int? shapeIndex = _shapeIndex(
            shapes: shapes,
            id: id,
            fallback: nextShapeIndex,
          );
          if (shapeIndex == null) {
            onIssue('Hierarchy preset ${index + 1} cannot be mapped to a decoded shape');
          } else if (shapeIndex >= nextShapeIndex) {
            nextShapeIndex = shapeIndex + 1;
          }
          entries.add(
            CshHierarchyEntry(
              index: index,
              kind: CshHierarchyEntryKind.preset,
              depth: depth,
              classId: classId,
              name: name ?? (shapeIndex == null ? null : shapes[shapeIndex].name),
              id: id ?? (shapeIndex == null ? null : shapes[shapeIndex].id),
              shapeIndex: shapeIndex,
              rawDescriptor: descriptor,
            ),
          );
        case 'null':
        case '':
          entries.add(
            CshHierarchyEntry(
              index: index,
              kind: CshHierarchyEntryKind.empty,
              depth: depth,
              classId: classId,
              name: name,
              id: id,
              shapeIndex: null,
              rawDescriptor: descriptor,
            ),
          );
        default:
          onIssue('Hierarchy entry ${index + 1} uses unknown class "$classId"');
          entries.add(
            CshHierarchyEntry(
              index: index,
              kind: CshHierarchyEntryKind.unknown,
              depth: depth,
              classId: classId,
              name: name,
              id: id,
              shapeIndex: null,
              rawDescriptor: descriptor,
            ),
          );
      }
    }
    if (depth != 0) {
      onIssue('CSH hierarchy ends with $depth unclosed group${depth == 1 ? '' : 's'}');
    }
    return entries;
  }

  /// Returns the first nonempty string stored under one of [keys].
  static String? _firstString(PsDescriptor descriptor, List<String> keys) {
    for (final String key in keys) {
      final PsDescriptorValue? value = descriptor.value(key);
      if (value case PsStringValue(:final String value) when value.isNotEmpty) {
        final String trimmed = _trimTerminalNulls(value);
        return trimmed.isEmpty ? null : trimmed;
      }
    }
    return null;
  }

  /// Removes only terminal null characters from [value].
  static String _trimTerminalNulls(String value) {
    int end = value.length;
    while (end > 0 && value.codeUnitAt(end - 1) == 0) {
      end--;
    }
    return value.substring(0, end);
  }

  /// Resolves a shape by [id] before applying its sequential [fallback].
  static int? _shapeIndex({
    required List<CshShape> shapes,
    required String? id,
    required int fallback,
  }) {
    if (id != null && id.isNotEmpty) {
      final int matched = shapes.lastIndexWhere((shape) => shape.id == id);
      if (matched >= 0) {
        return matched;
      }
    }
    return fallback < shapes.length ? fallback : null;
  }
}
