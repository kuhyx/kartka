import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/source_health/feed/reporting_feed.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

class _Feed implements SourceHealthFeed {
  final records = StreamController<List<SourceHealthRecord>>.broadcast();
  final meta = StreamController<SourceHealthMeta?>.broadcast();

  @override
  Stream<List<SourceHealthRecord>> watch() => records.stream;

  @override
  Stream<SourceHealthMeta?> watchMeta() => meta.stream;
}

void main() {
  test('a ranking read error is logged and still reaches the tab', () async {
    final inner = _Feed();
    final log = DiagnosticsLog(MemoryBlobStore());
    final feed = ReportingHealthFeed(inner, log);
    final seen = <Object>[];
    final metaSeen = <SourceHealthMeta?>[];
    feed.watch().listen((_) => seen.add('data'), onError: seen.add);
    feed.watchMeta().listen(metaSeen.add);
    inner.records
      ..add(const [])
      ..addError(StateError('reading source_health failed: HTTP 401'));
    inner.meta.add(null);
    await pumpEventQueue();
    expect(seen.first, 'data');
    expect(seen.last, isA<StateError>());
    expect(metaSeen, [null]);
    final e = (await log.entries()).single;
    expect(e.kind, 'health.read');
    expect(e.error, contains('HTTP 401'));
  });
}
