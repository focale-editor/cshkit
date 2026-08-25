import 'dart:typed_data';

import 'package:cshkit/cshkit.dart';

/// Describes one trailing tagged block used by synthetic CSH libraries.
final class CshTestTaggedBlock {
  /// Four-byte Photoshop signature.
  final String signature;

  /// Four-byte tagged-block key.
  final String key;

  /// Unpadded block payload.
  final Uint8List data;

  /// Explicit bytes written after the payload.
  final Uint8List paddingData;

  /// Creates a synthetic tagged block.
  CshTestTaggedBlock({
    required this.key,
    required Uint8List data,
    this.signature = '8BIM',
    Uint8List? paddingData,
  }) : data = Uint8List.fromList(data),
       paddingData = Uint8List.fromList(paddingData ?? Uint8List(0));
}

/// Builds compact deterministic CSH buffers for decoder tests.
abstract final class CshFixtureBuilder {
  /// Builds one complete CSH library from [shapes] and trailing [blocks].
  static Uint8List file({
    required List<Uint8List> shapes,
    List<CshTestTaggedBlock> blocks = const <CshTestTaggedBlock>[],
    List<int> trailingData = const <int>[],
    String signature = 'cush',
    int version = 2,
    int? declaredShapeCount,
  }) {
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeString(signature)
      ..writeUint32(version)
      ..writeUint32(declaredShapeCount ?? shapes.length);
    shapes.forEach(writer.writeBytes);
    for (final CshTestTaggedBlock block in blocks) {
      writer
        ..writeString(block.signature)
        ..writeString(block.key);
      if (block.signature == '8B64') {
        writer.writeUint64(block.data.length);
      } else {
        writer.writeUint32(block.data.length);
      }
      writer
        ..writeBytes(block.data)
        ..writeBytes(block.paddingData);
    }
    writer.writeBytes(trailingData);
    return writer.takeBytes();
  }

  /// Builds one length-bounded custom-shape record.
  static Uint8List shape({
    required String name,
    required String id,
    required CshRectangle bounds,
    required CshVectorPath path,
    int version = 1,
    bool terminateName = true,
    Uint8List? namePaddingData,
    Uint8List? pathPaddingData,
  }) {
    final PsBinaryWriter record = PsBinaryWriter();
    final List<int> nameCodeUnits = <int>[
      ...name.codeUnits,
      if (terminateName) 0,
    ];
    record.writeUint32(nameCodeUnits.length);
    nameCodeUnits.forEach(record.writeUint16);
    final int expectedNamePaddingLength = (4 - record.length % 4) % 4;
    final Uint8List resolvedNamePadding = namePaddingData ?? Uint8List(expectedNamePaddingLength);
    if (resolvedNamePadding.length != expectedNamePaddingLength) {
      throw ArgumentError.value(
        resolvedNamePadding.length,
        'namePaddingData',
        'must contain exactly $expectedNamePaddingLength bytes',
      );
    }
    record.writeBytes(resolvedNamePadding);

    final Uint8List encodedPath = PsVectorPathCodec.encode(path);
    final PsBinaryWriter body = PsBinaryWriter()
      ..writeUint8(id.length)
      ..writeString(id)
      ..writeInt32(bounds.top)
      ..writeInt32(bounds.left)
      ..writeInt32(bounds.bottom)
      ..writeInt32(bounds.right)
      ..writeBytes(encodedPath);
    final int expectedPathPaddingLength = (4 - body.length % 4) % 4;
    final Uint8List resolvedPathPadding = pathPaddingData ?? Uint8List(expectedPathPaddingLength);
    if (resolvedPathPadding.length != expectedPathPaddingLength) {
      throw ArgumentError.value(
        resolvedPathPadding.length,
        'pathPaddingData',
        'must contain exactly $expectedPathPaddingLength bytes',
      );
    }
    body.writeBytes(resolvedPathPadding);
    final Uint8List bodyData = body.takeBytes();
    record
      ..writeUint32(version)
      ..writeUint32(bodyData.length)
      ..writeBytes(bodyData);
    return record.takeBytes();
  }

  /// Builds a versioned `phry` block from ordered descriptor [entries].
  static CshTestTaggedBlock hierarchyBlock({
    required List<PsDescriptorValue> entries,
    int descriptorVersion = 16,
    Uint8List? paddingData,
  }) {
    final PsDescriptor root = PsDescriptor(
      name: '',
      classId: 'null',
      items: <PsDescriptorItem>[
        PsDescriptorItem(
          key: 'hierarchy',
          value: PsListValue(values: entries),
        ),
      ],
    );
    final PsBinaryWriter payload = PsBinaryWriter()
      ..writeUint32(descriptorVersion)
      ..writeBytes(PsDescriptorCodec.encode(root));
    return CshTestTaggedBlock(
      key: 'phry',
      data: payload.takeBytes(),
      paddingData: paddingData,
    );
  }

  /// Builds an unknown tagged block for forward-compatibility tests.
  static CshTestTaggedBlock unknownBlock({
    String signature = '8BIM',
    Uint8List? paddingData,
  }) => CshTestTaggedBlock(
    signature: signature,
    key: 'futr',
    data: Uint8List.fromList(<int>[1, 2, 3]),
    paddingData: paddingData,
  );

  /// Creates one nested hierarchy object with optional [name] and [id].
  static PsObjectValue hierarchyObject({
    required String classId,
    String? name,
    String? id,
  }) => PsObjectValue(
    value: PsDescriptor(
      name: '',
      classId: classId,
      items: <PsDescriptorItem>[
        if (name != null)
          PsDescriptorItem(
            key: 'Nm  ',
            value: PsStringValue(value: '$name\u0000'),
          ),
        if (id != null)
          PsDescriptorItem(
            key: 'zuid',
            value: PsStringValue(value: '$id\u0000'),
          ),
      ],
    ),
  );
}
