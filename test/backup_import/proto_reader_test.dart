import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/backup_import/proto_reader.dart';

Uint8List b(List<int> v) => Uint8List.fromList(v);

void main() {
  test('reads varint, string, bytes and nested messages', () {
    final r = ProtoReader(
      b([
        0x08, 0xAC, 0x02, // field 1 varint 300
        0x12, 0x02, 0x68, 0x69, // field 2 "hi"
        0x1A, 0x02, 0x08, 0x07, // field 3 message {1: 7}
      ]),
    );
    expect(r.next(), isTrue);
    expect((r.field, r.wireType), (1, 0));
    expect(r.varint(), 300);
    expect(r.next(), isTrue);
    expect(r.string(), 'hi');
    expect(r.next(), isTrue);
    final sub = r.message();
    expect(sub.next(), isTrue);
    expect(sub.varint(), 7);
    expect(sub.next(), isFalse);
    expect(r.next(), isFalse);
  });

  test('varintBig keeps full int64 precision', () {
    // 2499283573021220255 as varint.
    final v = BigInt.parse('2499283573021220255');
    final bytes = <int>[0x08];
    var x = v;
    while (x >= BigInt.from(0x80)) {
      bytes.add(((x & BigInt.from(0x7f)) | BigInt.from(0x80)).toInt());
      x >>= 7;
    }
    bytes.add(x.toInt());
    final r = ProtoReader(b(bytes))..next();
    expect(r.varintBig(), v);
    expect((ProtoReader(b(bytes))..next()).varint(), v.toInt());
  });

  test('negative int64 decodes via two complement', () {
    final r = ProtoReader(b([0x08, ...List.filled(9, 0xFF), 0x01]))..next();
    expect(r.varint(), -1);
  });

  test('float32, boolean and unicode strings', () {
    final data = ByteData(4)..setFloat32(0, 12.5, Endian.little);
    final text = utf8.encode('żółw');
    final r = ProtoReader(
      b([
        0x0D, ...data.buffer.asUint8List(), // field 1 fixed32
        0x10, 0x01, // field 2 bool true
        0x1A, text.length, ...text, // field 3 string
      ]),
    )..next();
    expect(r.float32(), 12.5);
    r.next();
    expect(r.boolean(), isTrue);
    r.next();
    expect(r.string(), 'żółw');
  });

  test('skip passes every wire type', () {
    final r = ProtoReader(
      b([
        0x08, 0x01, // varint
        0x11, 1, 2, 3, 4, 5, 6, 7, 8, // fixed64
        0x1A, 0x01, 0x00, // bytes
        0x25, 1, 2, 3, 4, // fixed32
        0x28, 0x05, // varint (field 5)
      ]),
    );
    final seen = <int>[];
    while (r.next()) {
      seen.add(r.field);
      r.skip();
    }
    expect(seen, [1, 2, 3, 4, 5]);
  });

  test('repeated ints accept packed and unpacked encodings', () {
    final out = <int>[];
    final r = ProtoReader(
      b([
        0x8A, 0x01, 0x03, 0x01, 0x02, 0x03, // field 17 packed [1,2,3]
        0x88, 0x01, 0x09, // field 17 varint 9
      ]),
    );
    while (r.next()) {
      r.readInts(out);
    }
    expect(out, [1, 2, 3, 9]);
  });

  test('malformed input throws FormatException', () {
    expect(
      () => (ProtoReader(b([0x08]))..next()).varint(),
      throwsFormatException,
    );
    expect(
      () => (ProtoReader(b([0x12, 0x05, 0x01]))..next()).bytes(),
      throwsFormatException,
    );
    expect(
      () => (ProtoReader(b([0x0B]))..next()).skip(),
      throwsFormatException,
    );
    expect(() => ProtoReader(b([0x80])).next(), throwsFormatException);
    expect(
      () => (ProtoReader(b([0x0D, 1, 2]))..next()).float32(),
      throwsFormatException,
    );
    expect(
      () => ProtoReader(b([...List.filled(11, 0xFF)])).next(),
      throwsFormatException,
    );
  });
}
