import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';

import '../support/fakes.dart';

void main() {
  late MemoryKv kv;
  late ReaderPrefs prefs;

  setUp(() {
    kv = MemoryKv();
    prefs = ReaderPrefs(kv);
  });

  test('settings default when nothing is stored, then round-trip', () async {
    expect(await prefs.settings(), const ReaderSettings());
    const s = ReaderSettings(prefetchAhead: 6);
    await prefs.saveSettings(s);
    expect(await prefs.settings(), s);
  });

  test('corrupt settings fall back to defaults', () async {
    kv.data[ReaderPrefs.settingsKey] = '{not json';
    expect(await prefs.settings(), const ReaderSettings());
    kv.data[ReaderPrefs.settingsKey] = '[1]';
    expect(await prefs.settings(), const ReaderSettings());
  });

  test('per-manga mode overrides the default and can be cleared', () async {
    const key = 'fake|/m/1';
    expect(await prefs.modeFor(key), isNull);
    await prefs.setModeFor(key, ReaderMode.webtoon);
    expect(await prefs.modeFor(key), ReaderMode.webtoon);
    expect(await prefs.modeFor('fake|/m/2'), isNull);
    expect(kv.data.keys.single, startsWith(ReaderPrefs.modePrefix));
    expect(kv.data.keys.single, isNot(contains('/m/1')));
    await prefs.setModeFor(key, null);
    expect(await prefs.modeFor(key), isNull);
    expect(kv.data, isEmpty);
  });

  test('effective mode prefers the manga, then the global default', () async {
    const key = 'fake|/m/1';
    await prefs.saveSettings(
      const ReaderSettings(defaultMode: ReaderMode.verticalPaged),
    );
    expect(await prefs.effectiveMode(key), ReaderMode.verticalPaged);
    await prefs.setModeFor(key, ReaderMode.pagedLtr);
    expect(await prefs.effectiveMode(key), ReaderMode.pagedLtr);
  });
}
