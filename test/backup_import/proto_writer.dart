import 'dart:convert';
import 'dart:typed_data';

/// Tiny protobuf encoder used only to build synthetic `.tachibk` fixtures.
class ProtoWriter {
  final BytesBuilder _out = BytesBuilder();

  /// Encoded bytes so far.
  Uint8List get bytes => _out.toBytes();

  void _tag(int field, int wire) => _varint((field << 3) | wire);

  void _varint(int value) {
    var v = value;
    while (v >= 0x80) {
      _out.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    _out.addByte(v);
  }

  /// Varint field; [BigInt] values keep full int64 precision.
  void int64(int field, Object value) {
    _tag(field, 0);
    if (value is BigInt) {
      var v = value;
      final mask = BigInt.from(0x7f);
      while (v >= BigInt.from(0x80)) {
        _out.addByte(((v & mask) | BigInt.from(0x80)).toInt());
        v >>= 7;
      }
      _out.addByte(v.toInt());
    } else {
      _varint(value as int);
    }
  }

  /// Boolean field.
  void boolean(int field, {required bool value}) => int64(field, value ? 1 : 0);

  /// UTF-8 string field.
  void string(int field, String value) => raw(field, utf8.encode(value));

  /// Length-delimited bytes field.
  void raw(int field, List<int> value) {
    _tag(field, 2);
    _varint(value.length);
    _out.add(value);
  }

  /// Embedded message field.
  void message(int field, ProtoWriter inner) => raw(field, inner.bytes);

  /// Float field.
  void float32(int field, double value) {
    _tag(field, 5);
    _out.add(
      (ByteData(4)..setFloat32(0, value, Endian.little)).buffer.asUint8List(),
    );
  }

  /// Packed repeated varint field.
  void packed(int field, List<int> values) {
    final inner = ProtoWriter();
    values.forEach(inner._varint);
    raw(field, inner.bytes);
  }
}
