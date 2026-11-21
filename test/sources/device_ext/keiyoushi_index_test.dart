import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/device_ext/keiyoushi_index.dart';

void main() {
  // The real index.pb (2026-11-21) cut down to MangaFire and Atsumaru.
  final bytes = File('test/fixtures/keiyoushi/index.pb').readAsBytesSync();

  test('reads MangaFire and Atsumaru from the real store index', () {
    final exts = {for (final e in parseKeiyoushiIndex(bytes)) e.pkg: e};
    final fire = exts['eu.kanade.tachiyomi.extension.all.mangafire']!;
    expect(fire.name, 'MangaFire');
    expect(fire.lib, '1.6');
    expect(fire.versionName, '1.6.38');
    expect(fire.apkUrl, endsWith('tachiyomi-all.mangafire-v1.6.38.apk'));
    expect(fire.sourceIds, contains('6084907896154116083'));
    expect(fire.lang, 'all');
    final atsu = exts['eu.kanade.tachiyomi.extension.en.atsumaru']!;
    expect(atsu.sourceIds, ['2327480808438768017']);
    expect(atsu.lang, 'en');
    expect(atsu.nsfw, isFalse);
    expect(atsu.iconUrl, startsWith('https://'));
    expect(atsu.versionCode, greaterThan(0));
  });

  test('an index without a list is empty; a bad wire type throws', () {
    final empty = Uint8List.fromList(const GZipEncoder().encodeBytes([]));
    expect(parseKeiyoushiIndex(empty), isEmpty);
    final bad = Uint8List.fromList(
      const GZipEncoder().encodeBytes([0x0b]), // field 1, wire type 3
    );
    expect(() => parseKeiyoushiIndex(bad), throwsFormatException);
  });

  test('fixed-width fields are skipped', () {
    // field 9 fixed64, field 10 fixed32, then field 101 with no extensions.
    final raw = [
      0x49,
      ...List.filled(8, 0),
      0x55,
      ...List.filled(4, 0),
      0xaa,
      0x06,
      0,
    ];
    final gz = Uint8List.fromList(const GZipEncoder().encodeBytes(raw));
    expect(parseKeiyoushiIndex(gz), isEmpty);
  });
}
