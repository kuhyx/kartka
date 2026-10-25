import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

const _secretUrl = 'https://h.example/p?key=SECRET';

DiagnosticEntry _entry(String error, {int minute = 0}) => DiagnosticEntry(
  at: DateTime.utc(2026, 10, 25, 12, minute),
  kind: 'test.kind',
  error: error,
);

/// A store whose reads or writes fail on demand.
class _FlakyStore extends MemoryBlobStore {
  bool failGet = false;
  bool failPut = false;

  @override
  Future<Uint8List?> get(String key) =>
      failGet ? Future.error(StateError('read')) : super.get(key);

  @override
  Future<void> put(String key, Uint8List bytes) =>
      failPut ? Future.error(StateError('write')) : super.put(key, bytes);
}

Future<String> _raw(BlobStore store) async =>
    utf8.decode((await store.get(DiagnosticsLog.defaultKey))!);

void main() {
  group('DiagnosticEntry', () {
    test('serialises UTC ISO-8601 and round-trips', () {
      final e = DiagnosticEntry(
        at: DateTime.parse('2026-10-25T14:00:00+02:00'),
        kind: 'reader.advance',
        error: 'boom',
        sourceId: 's',
        mangaUrl: '/m',
        chapterUrl: '/c',
        stack: const ['#0 a', '#1 b'],
      );
      final json = e.toJson();
      expect(json['at'], '2026-10-25T12:00:00.000Z');
      final back = DiagnosticEntry.fromJson(json);
      expect(back.toJson(), json);
      expect(back.at.isUtc, isTrue);
      expect(back.stack, ['#0 a', '#1 b']);
    });

    test('optional fields are omitted and read back as null', () {
      final json = _entry('x').toJson();
      expect(json.keys, ['at', 'kind', 'error']);
      final back = DiagnosticEntry.fromJson(json);
      expect(back.sourceId, isNull);
      expect(back.stack, isEmpty);
    });

    test('every string field is redacted', () {
      final e = DiagnosticEntry(
        at: DateTime.utc(2026),
        kind: 'k $_secretUrl',
        error: 'failed $_secretUrl',
        sourceId: _secretUrl,
        mangaUrl: _secretUrl,
        chapterUrl: _secretUrl,
        stack: const ['#0 $_secretUrl'],
      );
      final text = jsonEncode(e.toJson());
      expect(text, isNot(contains('SECRET')));
      expect(text, contains('https://h.example/p?<redacted>'));
    });

    test('failure() keeps the top frames and caps the error', () {
      final stack = StackTrace.fromString(
        List.generate(9, (i) => '#$i frame$i ($_secretUrl)').join('\n'),
      );
      final e = DiagnosticEntry.failure(
        at: DateTime.utc(2026),
        kind: 'k',
        error: StateError('x' * 5000),
        stack: stack,
      );
      expect(e.stack, hasLength(DiagnosticEntry.maxFrames));
      expect(e.stack.first, startsWith('#0 frame0'));
      expect(e.error.length, DiagnosticEntry.maxErrorLength);
      expect(jsonEncode(e.toJson()), isNot(contains('SECRET')));
      final bare = DiagnosticEntry.failure(at: DateTime.utc(2026), kind: 'k');
      expect(bare.error, 'unknown error');
      expect(bare.stack, isEmpty);
    });
  });

  group('DiagnosticsLog', () {
    test('appends JSON lines in order and reads them back', () async {
      final store = MemoryBlobStore();
      final log = DiagnosticsLog(store);
      expect(await log.entries(), isEmpty);
      await Future.wait([log.append(_entry('a')), log.append(_entry('b'))]);
      final raw = await _raw(store);
      expect(raw.split('\n'), hasLength(3));
      expect(raw, endsWith('\n'));
      expect((await log.entries()).map((e) => e.error), ['a', 'b']);
    });

    test('continues an existing file instead of replacing it', () async {
      final store = MemoryBlobStore();
      await DiagnosticsLog(store).append(_entry('old'));
      await DiagnosticsLog(store).append(_entry('new'));
      final errors = (await DiagnosticsLog(
        store,
      ).entries()).map((e) => e.error);
      expect(errors, ['old', 'new']);
    });

    test('rolls the oldest entries off past the entry cap', () async {
      final store = MemoryBlobStore();
      final log = DiagnosticsLog(store, maxEntries: 3);
      for (var i = 0; i < 5; i++) {
        await log.append(_entry('e$i', minute: i));
      }
      expect((await log.entries()).map((e) => e.error), ['e2', 'e3', 'e4']);
    });

    test('rolls the oldest entries off past the byte cap', () async {
      final store = MemoryBlobStore();
      final line = utf8.encode(jsonEncode(_entry('e0').toJson())).length + 1;
      final log = DiagnosticsLog(store, maxBytes: line * 2);
      for (var i = 0; i < 4; i++) {
        await log.append(_entry('e$i'));
      }
      expect(
        utf8.encode(await _raw(store)).length,
        lessThanOrEqualTo(line * 2),
      );
      expect((await log.entries()).map((e) => e.error), ['e2', 'e3']);
    });

    test('skips unreadable lines', () async {
      final store = MemoryBlobStore();
      await store.put(
        DiagnosticsLog.defaultKey,
        utf8.encode('not json\n[1]\n${jsonEncode(_entry('ok').toJson())}\n'),
      );
      final log = DiagnosticsLog(store);
      expect((await log.entries()).map((e) => e.error), ['ok']);
    });

    test('never throws; a failed read keeps the file intact', () async {
      final store = _FlakyStore();
      final log = DiagnosticsLog(store);
      await log.append(_entry('kept'));
      final fresh = DiagnosticsLog(store);
      store.failGet = true;
      await fresh.append(_entry('lost'));
      expect(await fresh.entries(), isEmpty);
      store
        ..failGet = false
        ..failPut = true;
      await log.append(_entry('unwritten'));
      store.failPut = false;
      await log.append(_entry('later'));
      final errors = (await DiagnosticsLog(
        store,
      ).entries()).map((e) => e.error);
      expect(errors, ['kept', 'unwritten', 'later']);
    });

    test('of() shares one log per store', () {
      final a = MemoryBlobStore();
      expect(DiagnosticsLog.of(a), same(DiagnosticsLog.of(a)));
      expect(
        DiagnosticsLog.of(a),
        isNot(same(DiagnosticsLog.of(MemoryBlobStore()))),
      );
    });
  });
}
