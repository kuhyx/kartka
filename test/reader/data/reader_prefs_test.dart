import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';

void main() {
  late MemoryKeyValueStore kv;
  late ReaderPrefs prefs;

  setUp(() {
    kv = MemoryKeyValueStore();
    prefs = ReaderPrefs(kv);
  });

  test('settings default when nothing is stored, then round-trip', () async {
    expect(await prefs.settings(), const ReaderSettings());
    const s = ReaderSettings(prefetchAhead: 6);
    await prefs.saveSettings(s);
    expect(await prefs.settings(), s);
  });

  test('corrupt settings fall back to defaults', () async {
    await kv.set(ReaderPrefs.settingsKey, '{not json');
    expect(await prefs.settings(), const ReaderSettings());
    await kv.set(ReaderPrefs.settingsKey, '[1]');
    expect(await prefs.settings(), const ReaderSettings());
  });

  test('per-manga mode overrides the default and can be cleared', () async {
    const key = 'fake|/m/1';
    expect(await prefs.modeFor(key), isNull);
    await prefs.setModeFor(key, ReaderMode.webtoon);
    expect(await prefs.modeFor(key), ReaderMode.webtoon);
    expect(await prefs.modeFor('fake|/m/2'), isNull);
    final stored = (await kv.entries()).keys.single;
    expect(stored, startsWith(ReaderPrefs.modePrefix));
    expect(stored, isNot(contains('/m/1')));
    await prefs.setModeFor(key, null);
    expect(await prefs.modeFor(key), isNull);
    expect(await kv.entries(), isEmpty);
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
