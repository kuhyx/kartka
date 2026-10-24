import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'proto_writer.dart';

/// MangaDex (en) in Tachiyomi's numeric source id space.
final BigInt mangaDexEn = BigInt.parse('2499283573021220255');

/// MangaDex (de), see `md5("mangadex/de/1")`.
final BigInt mangaDexDe = BigInt.parse('5098537545549490547');

/// A generic extension source served by Suwayomi ("AllManga").
final BigInt allManga = BigInt.parse('4709139914729853090');

const String mdUuid = '8d90d411-8ead-49bd-9d16-0139f6b76700';
const String mdUuid2 = '11111111-2222-3333-4444-555555555555';
const String mdUuid3 = '99999999-8888-7777-6666-555555555555';

ProtoWriter _chapter(
  String url,
  double number, {
  bool read = false,
  int page = 0,
  int order = 0,
}) {
  final w = ProtoWriter()
    ..string(1, url)
    ..string(2, 'Chapter $number');
  if (read) w.boolean(4, value: true);
  if (page > 0) w.int64(6, page);
  return w
    ..float32(9, number)
    ..int64(10, order);
}

ProtoWriter _track(int sync, BigInt mediaId, double last) => ProtoWriter()
  ..int64(1, sync)
  ..string(4, 'https://tracker.example/$sync')
  ..float32(6, last)
  ..int64(100, mediaId);

ProtoWriter _history(String url, int lastRead) => ProtoWriter()
  ..string(1, url)
  ..int64(2, lastRead)
  ..int64(3, 1000);

ProtoWriter _manga(
  BigInt source,
  String url,
  String title, {
  List<ProtoWriter> chapters = const [],
  List<ProtoWriter> tracking = const [],
  List<ProtoWriter> history = const [],
  bool favorite = true,
}) {
  final w = ProtoWriter()
    ..int64(1, source)
    ..string(2, url)
    ..string(3, title)
    ..string(5, 'Some Author')
    ..string(7, 'Romance')
    ..string(7, 'Comedy')
    ..int64(8, 2)
    ..string(9, 'https://cover.example/$title.jpg')
    ..int64(13, 1666622369105);
  for (final c in chapters) {
    w.message(16, c);
  }
  for (final t in tracking) {
    w.message(18, t);
  }
  if (!favorite) w.boolean(100, value: false);
  for (final h in history) {
    w.message(104, h);
  }
  return w..int64(106, 1700000600);
}

/// Builds the raw (uncompressed) protobuf of the synthetic SY backup.
Uint8List buildSyntheticProto() {
  final dex = _manga(
    mangaDexEn,
    '/manga/$mdUuid',
    'Dex One',
    chapters: [
      _chapter('/chapter/c1', 1, read: true, page: 3, order: 3),
      _chapter('/chapter/c2', 2, read: true, page: 7, order: 2),
      _chapter('/chapter/c3', 3, read: true, page: 4, order: 1),
      _chapter('/chapter/c4', 4),
    ],
    tracking: [
      _track(2, BigInt.from(134187), 3),
      _track(1, BigInt.from(139022), 3),
      _track(7, BigInt.parse('57847596550'), 3),
    ],
    history: [
      _history('/chapter/c2', 1700000000000),
      _history('/chapter/c3', 1700000500000),
    ],
  )..int64(17, 0);

  final de = _manga(mangaDexDe, '/manga/$mdUuid2', 'Dex Zwei');

  final suwayomi = _manga(
    allManga,
    '/manga/abc123',
    'Allmanga Title',
    chapters: [
      _chapter('/ch/10', 10, read: true, page: 20),
      _chapter('/ch/11', 11, page: 5),
    ],
  )..packed(17, [0, 1]);

  // SY extras: custom overrides, merged refs, flat metadata, unknown field.
  final merged = ProtoWriter()
    ..boolean(1, value: true)
    ..string(6, 'merge://x')
    ..string(7, '/manga/merged')
    ..int64(8, allManga);
  final sy =
      _manga(
          allManga,
          '/manga/sy-extras',
          'Original Title',
          chapters: [_chapter('/ch/unnumbered', -1, read: true)],
        )
        ..message(600, merged)
        ..message(601, ProtoWriter()..string(1, 'flat'))
        ..int64(602, 3)
        ..string(603, 'https://custom.example/cover.png')
        ..string(800, 'My Custom Title')
        ..int64(9999, 1);

  final eh = _manga(
    BigInt.from(6901),
    '/g/1234567/abcdef0123/',
    'EH gallery',
    chapters: [_chapter('/g/1234567/abcdef0123/', 1, read: true)],
  );
  final local = _manga(BigInt.zero, 'My Local Manga', 'Local Manga');
  final dropped = _manga(
    mangaDexEn,
    '/manga/$mdUuid3',
    'Not In Library',
    favorite: false,
    history: [_history('/chapter/z', 1600000000000)],
  );

  final root = ProtoWriter();
  for (final m in [dex, de, suwayomi, sy, eh, local, dropped]) {
    root.message(1, m);
  }
  for (final (i, name) in ['Reading', 'Later', 'Empty'].indexed) {
    final c = ProtoWriter()
      ..string(1, name)
      ..int64(3, i + 1);
    if (i > 0) c.int64(2, i);
    root.message(2, c);
  }
  for (final (name, id) in [
    ('MangaDex', mangaDexEn),
    ('AllManga', allManga),
    ('E-Hentai', BigInt.from(6901)),
  ]) {
    root.message(
      101,
      ProtoWriter()
        ..string(1, name)
        ..int64(2, id),
    );
  }
  root
    ..message(104, ProtoWriter()..string(1, 'pref'))
    ..message(106, ProtoWriter()..string(1, 'store'))
    ..message(600, ProtoWriter()..string(1, 'saved search'));
  return root.bytes;
}

/// The synthetic backup gzipped, exactly like a real `.tachibk`.
Uint8List buildSyntheticTachibk() =>
    Uint8List.fromList(const GZipEncoder().encode(buildSyntheticProto()));
