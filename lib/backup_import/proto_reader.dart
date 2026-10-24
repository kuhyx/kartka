import 'dart:convert';
import 'dart:typed_data';

/// Minimal protobuf wire-format reader (varint, fixed32/64, length-delimited).
///
/// Written from the public wire-format documentation
/// (protobuf.dev/programming-guides/encoding). Iterate fields with [next],
/// then consume the current field with exactly one of the read methods or
/// [skip]. Integers are web-safe: ordinary [varint] values below 2^53 are
/// exact on dart2js; use [varintBig] where full int64 matters (source ids).
class ProtoReader {
  /// Reads the whole of [bytes], or the `[start, end)` slice of it.
  ProtoReader(this._bytes, [this._pos = 0, int? end])
    : _end = end ?? _bytes.length;

  final Uint8List _bytes;
  final int _end;
  int _pos;

  /// Field number of the current field (valid after [next] returned true).
  int field = 0;

  /// Wire type of the current field: 0 varint, 1 fixed64, 2 bytes, 5 fixed32.
  int wireType = 0;

  /// Advances to the next field; false at the end of the message.
  bool next() {
    if (_pos >= _end) return false;
    final tag = _varintBig(maxBytes: 5);
    field = (tag >> 3).toInt();
    wireType = (tag & BigInt.from(7)).toInt();
    return true;
  }

  /// Current varint field as an int (two's complement for negative int64).
  int varint() {
    final start = _pos;
    final fast = _fastVarint();
    if (fast != null) return fast;
    _pos = start;
    return _varintBig().toSigned(64).toInt();
  }

  /// Current varint field with full 64-bit precision, as signed [BigInt].
  BigInt varintBig() => _varintBig().toSigned(64);

  /// Current varint field as a boolean.
  bool boolean() => varint() != 0;

  /// Current length-delimited field as a byte view (no copy).
  Uint8List bytes() {
    final length = varint();
    if (length < 0 || _pos + length > _end) {
      throw const FormatException('Truncated length-delimited field');
    }
    final view = Uint8List.sublistView(_bytes, _pos, _pos + length);
    _pos += length;
    return view;
  }

  /// Current length-delimited field as UTF-8 text.
  String string() => utf8.decode(bytes(), allowMalformed: true);

  /// Current length-delimited field as a nested message reader.
  ProtoReader message() {
    final length = varint();
    if (length < 0 || _pos + length > _end) {
      throw const FormatException('Truncated embedded message');
    }
    final sub = ProtoReader(_bytes, _pos, _pos + length);
    _pos += length;
    return sub;
  }

  /// Current fixed32 field as a little-endian float.
  double float32() {
    if (_pos + 4 > _end) throw const FormatException('Truncated fixed32');
    final v = ByteData.sublistView(
      _bytes,
      _pos,
      _pos + 4,
    ).getFloat32(0, Endian.little);
    _pos += 4;
    return v;
  }

  /// Appends the current repeated-int field to [out], packed or not.
  void readInts(List<int> out) {
    if (wireType != 2) {
      out.add(varint());
      return;
    }
    final packed = message();
    while (packed._pos < packed._end) {
      out.add(packed.varint());
    }
  }

  /// Discards the current field, whatever its type.
  void skip() {
    switch (wireType) {
      case 0:
        _varintBig();
      case 1:
        _advance(8);
      case 2:
        _advance(varint());
      case 5:
        _advance(4);
      default:
        throw FormatException('Unsupported wire type $wireType');
    }
  }

  void _advance(int count) {
    if (count < 0 || _pos + count > _end) {
      throw const FormatException('Truncated field');
    }
    _pos += count;
  }

  /// Exact for up to 7 bytes (49 bits); null means "use the BigInt path".
  int? _fastVarint() {
    var result = 0;
    var scale = 1;
    for (var i = 0; i < 7; i++) {
      if (_pos >= _end) throw const FormatException('Truncated varint');
      final byte = _bytes[_pos++];
      result += (byte & 0x7f) * scale;
      if (byte < 0x80) return result;
      scale *= 128;
    }
    return null;
  }

  BigInt _varintBig({int maxBytes = 10}) {
    var result = BigInt.zero;
    for (var i = 0; i < maxBytes; i++) {
      if (_pos >= _end) throw const FormatException('Truncated varint');
      final byte = _bytes[_pos++];
      result |= BigInt.from(byte & 0x7f) << (7 * i);
      if (byte < 0x80) return result;
    }
    throw const FormatException('Varint too long');
  }
}
