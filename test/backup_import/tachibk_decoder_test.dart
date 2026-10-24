import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/backup_import/tachibk_decoder.dart';

import 'fixture_builder.dart';
import 'proto_writer.dart';

void main() {
  final decoded = decodeTachibk(buildSyntheticTachibk());

  test('top level: manga, categories, sources', () {
    expect(decoded.manga, hasLength(7));
    expect(decoded.categories.map((c) => c.name), [
      'Reading',
      'Later',
      'Empty',
    ]);
    expect(decoded.categories.map((c) => (c.order, c.id)), [
      (0, 1),
      (1, 2),
      (2, 3),
    ]);
    expect(decoded.sources.map((s) => (s.name, s.sourceId)), [
      ('MangaDex', '2499283573021220255'),
      ('AllManga', '4709139914729853090'),
      ('E-Hentai', '6901'),
    ]);
  });

  test('manga scalar fields and full int64 source id', () {
    final m = decoded.manga.first;
    expect(m.sourceId, '2499283573021220255');
    expect(m.url, '/manga/$mdUuid');
    expect(m.title, 'Dex One');
    expect(m.author, 'Some Author');
    expect(m.genres, ['Romance', 'Comedy']);
    expect(m.status, 2);
    expect(m.thumbnailUrl, 'https://cover.example/Dex One.jpg');
    expect(m.dateAdded, 1666622369105);
    expect(m.lastModifiedAt, 1700000600);
    expect(m.favorite, isTrue);
    expect(m.categories, [0]);
  });

  test('chapters, history and trackers', () {
    final m = decoded.manga.first;
    expect(m.chapters, hasLength(4));
    final c = m.chapters[2];
    expect(c.url, '/chapter/c3');
    expect(c.read, isTrue);
    expect(c.lastPageRead, 4);
    expect(c.number, 3.0);
    expect(c.sourceOrder, 1);
    expect(m.chapters[3].read, isFalse);
    expect(m.history.map((h) => (h.url, h.lastRead)), [
      ('/chapter/c2', 1700000000000),
      ('/chapter/c3', 1700000500000),
    ]);
    expect(m.tracking.map((t) => (t.syncId, t.mediaId)), [
      (2, '134187'),
      (1, '139022'),
      (7, '57847596550'),
      (3, '60625'),
    ]);
    expect(m.tracking.first.lastChapterRead, 3.0);
  });

  test('favorite defaults to true, false is kept', () {
    expect(decoded.manga[1].favorite, isTrue);
    expect(decoded.manga.last.favorite, isFalse);
    expect(decoded.manga.last.title, 'Not In Library');
  });

  test('packed categories and SY extras are decoded', () {
    expect(decoded.manga[2].categories, [0, 1]);
    final sy = decoded.manga[3];
    expect(sy.customTitle, 'My Custom Title');
    expect(sy.customThumbnailUrl, 'https://custom.example/cover.png');
    expect(sy.customStatus, 3);
    expect(sy.hasFlatMetadata, isTrue);
    expect(sy.mergedReferences.single.mangaUrl, '/manga/merged');
    expect(sy.mergedReferences.single.mangaSourceId, '4709139914729853090');
    expect(sy.mergedReferences.single.isInfoManga, isTrue);
    expect(sy.chapters.single.number, -1.0);
  });

  test('tracker mediaId falls back to the deprecated int field 3', () {
    final manga = ProtoWriter()
      ..message(
        18,
        ProtoWriter()
          ..int64(1, 2)
          ..int64(3, 42),
      );
    final root = ProtoWriter()..message(1, manga);
    final data = decodeTachibk(root.bytes);
    expect(data.manga.single.tracking.single.mediaId, '42');
  });

  test('unknown fields are skipped in every message type', () {
    ProtoWriter unknown(ProtoWriter w) => w..int64(999, 1);
    final manga = unknown(ProtoWriter())
      ..message(16, unknown(ProtoWriter()..string(1, '/c')))
      ..message(18, unknown(ProtoWriter()..string(5, 'Tracked title')))
      ..message(104, unknown(ProtoWriter()..string(1, '/c')))
      ..message(600, unknown(ProtoWriter()..boolean(1, value: false)));
    final root = unknown(ProtoWriter())
      ..message(1, manga)
      ..message(2, unknown(ProtoWriter()..string(1, 'c')))
      ..message(101, unknown(ProtoWriter()..string(1, 's')));
    final data = decodeTachibk(root.bytes);
    expect(data.manga.single.tracking.single.title, 'Tracked title');
    expect(data.manga.single.chapters.single.url, '/c');
    expect(data.categories.single.name, 'c');
    expect(data.sources.single.name, 's');
    expect(
      const BackupFormatException('x').toString(),
      'BackupFormatException: x',
    );
  });

  test('also accepts an uncompressed protobuf', () {
    final raw = decodeTachibk(buildSyntheticProto());
    expect(raw.manga, hasLength(7));
  });

  test('rejects garbage', () {
    expect(
      () => decodeTachibk(Uint8List.fromList([0x1f, 0x8b, 1, 2, 3])),
      throwsA(isA<BackupFormatException>()),
    );
    expect(
      () => decodeTachibk(Uint8List.fromList([0x0A, 0x7F])),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('committed synthetic fixture matches the builder', () {
    final file = File('test/fixtures/backup_import/synthetic.tachibk');
    final fromFile = decodeTachibk(file.readAsBytesSync());
    expect(
      fromFile.manga.map((m) => m.title),
      decoded.manga.map((m) => m.title),
    );
  });
}
