import 'package:cshkit/src/model/csh_shape.dart';
import 'package:pscore/pscore.dart';

/// Identifies the role of one slot in Photoshop's optional shape hierarchy.
enum CshHierarchyEntryKind {
  /// Opens a named shape group.
  groupStart,

  /// Closes the most recently opened shape group.
  groupEnd,

  /// Refers to a custom-shape preset.
  preset,

  /// Preserves an intentionally empty hierarchy slot.
  empty,

  /// Preserves an object class not understood by this release.
  unknown,
}

/// One ordered item from a trailing Photoshop `phry` hierarchy descriptor.
final class CshHierarchyEntry {
  /// Zero-based position in the flattened hierarchy.
  final int index;

  /// Semantic role inferred from the descriptor class.
  final CshHierarchyEntryKind kind;

  /// Zero-based nesting depth at which this item appears.
  final int depth;

  /// Original Photoshop descriptor class, or `null` for an empty slot.
  final String? classId;

  /// User-visible group or preset name, when stored.
  final String? name;

  /// Photoshop identifier associated with the item, when stored.
  final String? id;

  /// Index of the referred shape, when this is a mapped preset.
  final int? shapeIndex;

  /// Complete source descriptor, or `null` for an empty slot.
  final PsDescriptor? rawDescriptor;

  /// Creates an immutable hierarchy item.
  const CshHierarchyEntry({
    required this.index,
    required this.kind,
    required this.depth,
    required this.classId,
    required this.name,
    required this.id,
    required this.shapeIndex,
    required this.rawDescriptor,
  });

  /// Returns the referred custom shape from [shapes], when available.
  CshShape? resolveShape(List<CshShape> shapes) {
    final int? index = shapeIndex;
    if (index == null || index < 0 || index >= shapes.length) {
      return null;
    }
    return shapes[index];
  }
}
