import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/core/diagnostics/upload_rule.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/source_health/install/extension_autoupdate.dart';
import 'package:kartka/source_health/install/install_ports.dart';

import 'autoinstall_fakes.dart';

void main() {
  late MemoryKeyValueStore kv;
  late DiagnosticsLog log;
  late DateTime clock;
  setUp(() {
    kv = MemoryKeyValueStore();
    log = DiagnosticsLog(MemoryBlobStore());
    clock = DateTime.utc(2026, 11, 21, 8);
  });

  ExtensionAutoUpdater updater(
    SuwayomiExtensionUpdater? side, {
    bool agent = false,
  }) => ExtensionAutoUpdater(
    kv: kv,
    updater: () => side,
    diagnostics: log,
    now: () => clock,
    isAgent: () async => agent,
  );

  test('updates every outdated extension, at most 2 at a time, and logs '
      'counts and package names only', () async {
    final side = FakeUpdater({'pkg.a', 'pkg.b', 'pkg.c'})
      ..failing['pkg.b'] = StateError('HTTP 500 at http://host/x?token=1');
    final result = await updater(side).run();
    expect(side.calls.first, 'list');
    expect(side.calls.skip(1), {
      'update:pkg.a',
      'update:pkg.b',
      'update:pkg.c',
    });
    expect(side.maxInFlight, lessThanOrEqualTo(2));
    expect(result!.updated, ['pkg.a', 'pkg.c']);
    expect(result.failed, ['pkg.b']);
    final entries = await log.entries();
    expect(entries, hasLength(1));
    expect(entries.single.kind, autoUpdateKind);
    expect(entries.single.error, 'updated 2 [pkg.a, pkg.c], failed 1 [pkg.b]');
    expect(isUploadedEntry(entries.single), isTrue);
  });

  test('a clean run stays on the device (no board ticket)', () async {
    await updater(FakeUpdater({'pkg.a'})).run();
    final entry = (await log.entries()).single;
    expect(entry.error, 'updated 1 [pkg.a]');
    expect(isUploadedEntry(entry), isFalse);
  });

  test('runs at most once per 24 h, and once per instance', () async {
    final side = FakeUpdater({'pkg.a'});
    final first = updater(side);
    await first.run();
    expect(await first.run(), isNull);
    clock = clock.add(const Duration(hours: 23));
    expect(await updater(side).run(), isNull);
    expect(side.calls, ['list', 'update:pkg.a']);
    clock = clock.add(const Duration(hours: 1));
    side.outdated.add('pkg.b');
    await updater(side).run();
    expect(side.calls.last, 'update:pkg.b');
  });

  test('nothing outdated: no update, no log, the day still counts', () async {
    final side = FakeUpdater({});
    final result = await updater(side).run();
    expect(result!.updated, isEmpty);
    expect(await log.entries(), isEmpty);
    expect(await updater(side).run(), isNull);
  });

  test('an unreadable list is retried on the next start', () async {
    final side = FakeUpdater({'pkg.a'})..listError = StateError('down');
    expect(await updater(side).run(), isNull);
    side.listError = null;
    await updater(side).run();
    expect(side.calls, ['list', 'list', 'update:pkg.a']);
  });

  test('the agent instance never updates the shared server', () async {
    final side = FakeUpdater({'pkg.a'});
    expect(await updater(side, agent: true).run(), isNull);
    expect(side.calls, isEmpty);
    expect(await kv.entries(), isEmpty);
  });

  test('no Suwayomi part: nothing to do', () async {
    expect(await updater(null).run(), isNull);
    expect(await kv.entries(), isEmpty);
  });
}
