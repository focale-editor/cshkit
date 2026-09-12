import 'dart:typed_data';

import 'package:cshkit/src/model/csh_hierarchy.dart';
import 'package:cshkit/src/model/csh_options.dart';
import 'package:cshkit/src/model/csh_shape.dart';
import 'package:pscore/pscore.dart';

/// Backward-compatible name for a shared Photoshop tagged block.
typedef CshTaggedBlock = PsTaggedBlock;

/// Complete decoded contents of one Adobe Photoshop custom-shape library.
final class CshFile {
  /// Four-byte container signature exactly as stored.
  final String signature;

  /// CSH container version exactly as stored.
  final int version;

  /// Shape count declared by the CSH header.
  final int declaredShapeCount;

  /// Successfully decoded custom shapes in source order.
  final List<CshShape> shapes;

  /// Flattened group and preset hierarchy from recognized `phry` blocks.
  final List<CshHierarchyEntry> hierarchy;

  /// Complete root descriptors from every recognized `phry` block.
  final List<PsDescriptor> hierarchyDescriptors;

  /// Every trailing tagged block, including unknown forward-compatible keys.
  final List<CshTaggedBlock> taggedBlocks;

  /// Bytes following the last recognized shape or tagged block.
  final Uint8List trailingData;

  /// Number of unrecognized trailing bytes, even when preservation is disabled.
  final int trailingByteCount;

  /// Recoverable compatibility issues encountered while decoding.
  final List<CshWarning> warnings;

  /// Last shape for every non-empty identifier.
  final Map<String, CshShape> _shapesById;

  /// Creates an immutable decoded CSH library.
  CshFile({
    required this.signature,
    required this.version,
    required this.declaredShapeCount,
    required List<CshShape> shapes,
    required List<CshHierarchyEntry> hierarchy,
    required List<PsDescriptor> hierarchyDescriptors,
    required List<CshTaggedBlock> taggedBlocks,
    required Uint8List trailingData,
    required this.trailingByteCount,
    required List<CshWarning> warnings,
  }) : shapes = List<CshShape>.unmodifiable(shapes),
       hierarchy = List<CshHierarchyEntry>.unmodifiable(hierarchy),
       hierarchyDescriptors = List<PsDescriptor>.unmodifiable(hierarchyDescriptors),
       taggedBlocks = List<CshTaggedBlock>.unmodifiable(taggedBlocks),
       trailingData = Uint8List.fromList(trailingData).asUnmodifiableView(),
       warnings = List<CshWarning>.unmodifiable(warnings),
       _shapesById = Map<String, CshShape>.unmodifiable(<String, CshShape>{
         for (final CshShape shape in shapes)
           if (shape.id.isNotEmpty) shape.id: shape,
       });

  /// Whether every shape declared in the header was decoded.
  bool get isComplete => shapes.length == declaredShapeCount;

  /// Returns the last shape matching [id], or `null` when absent.
  CshShape? shapeById(String id) => _shapesById[id];

  /// Resolves the shape referred to by [entry], when available.
  CshShape? shapeFor(CshHierarchyEntry entry) => entry.resolveShape(shapes);
}
