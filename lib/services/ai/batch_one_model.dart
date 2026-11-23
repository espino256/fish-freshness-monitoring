import 'dart:typed_data';

/// Specialize *shape signatures* to the already allocated batch-one shapes.
/// LiteRT.js requires static dimensions. Original files/weights are untouched.
/// Field indices follow TensorFlow schema v3: Model.subgraphs=2,
/// SubGraph.tensors=0, Tensor.shape=0, Tensor.shape_signature=7.
Uint8List specializeBatchOne(Uint8List original) {
  if (original.length < 8 ||
      String.fromCharCodes(original.sublist(4, 8)) != 'TFL3') {
    throw const FormatException('Expected a TFL3 model.');
  }
  final copy = Uint8List.fromList(original);
  final data = ByteData.sublistView(copy);
  int u32(int p) => data.getUint32(p, Endian.little);
  int i32(int p) => data.getInt32(p, Endian.little);
  int u16(int p) => data.getUint16(p, Endian.little);
  int indirect(int p) => p + u32(p);
  int? field(int table, int index) {
    final vtable = table - i32(table);
    final entry = vtable + 4 + index * 2;
    if (entry >= vtable + u16(vtable)) return null;
    final offset = u16(entry);
    return offset == 0 ? null : table + offset;
  }

  List<int> tables(int table, int index) {
    final position = field(table, index);
    if (position == null) return [];
    final vector = indirect(position);
    final length = u32(vector);
    if (length > (copy.length - vector - 4) ~/ 4) {
      throw const FormatException('Invalid model table vector.');
    }
    return List.generate(length, (i) => indirect(vector + 4 + i * 4));
  }

  for (final graph in tables(u32(0), 2)) {
    for (final tensor in tables(graph, 0)) {
      final shapeField = field(tensor, 0);
      final signatureField = field(tensor, 7);
      if (shapeField == null || signatureField == null) continue;
      final shape = indirect(shapeField);
      final signature = indirect(signatureField);
      final rank = u32(shape);
      if (rank != u32(signature) || rank > (copy.length - signature - 4) ~/ 4) {
        throw const FormatException('Inconsistent shape signature.');
      }
      for (var axis = 0; axis < rank; axis++) {
        final concrete = i32(shape + 4 + axis * 4);
        final position = signature + 4 + axis * 4;
        final declared = i32(position);
        if (declared == -1 && axis == 0 && concrete == 1) {
          data.setInt32(position, 1, Endian.little);
        } else if (declared != concrete) {
          throw const FormatException(
            'Only a dynamic batch with concrete size one is supported.',
          );
        }
      }
    }
  }
  return copy;
}
