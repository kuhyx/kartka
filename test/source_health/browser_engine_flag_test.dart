import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/cut_reasons.dart';
import 'package:kartka/source_health/feed/fixture_feed.dart';
import 'package:kartka/source_health/metric_explanations.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/source_health_lookup_impl.dart';

const allManga = SourceHealthRecord(
  id: 'suwayomi:allmanga',
  name: 'AllManga',
  blocking: BlockingMetric(challengeRate: 0.06, kinds: ['webview']),
  flags: ['needs-browser-engine'],
  verdict: HealthVerdict.keep,
  rank: 2,
);

void main() {
  group('§5 flags', () {
    test('parse, expose needsBrowserEngine and round-trip', () {
      final r = SourceHealthRecord.fromJson({
        'id': 'x',
        'flags': ['needs-browser-engine', 'future-flag', 7],
      })!;
      expect(r.flags, ['needs-browser-engine', 'future-flag']);
      expect(r.needsBrowserEngine, isTrue);
      expect(SourceHealthRecord.fromJson(r.toJson()), r);
      expect(r.toJson()['flags'], ['needs-browser-engine', 'future-flag']);
    });

    test('a record without flags (older evaluator) reads as none', () {
      final r = SourceHealthRecord.fromJson({'id': 'x'})!;
      expect(r.flags, isEmpty);
      expect(r.needsBrowserEngine, isFalse);
      expect(r.toJson().containsKey('flags'), isFalse);
      final odd = SourceHealthRecord.fromJson({'id': 'x', 'flags': 'a'});
      expect(odd!.flags, isEmpty);
    });

    test('flags take part in equality and hashCode', () {
      final a = SourceHealthRecord.fromJson(allManga.toJson())!;
      expect(a, allManga);
      expect(a.hashCode, allManga.hashCode);
      expect(a, isNot(SourceHealthRecord.fromJson({'id': allManga.id})));
    });
  });

  group('webview blocking is flagged, not cut', () {
    test('onlyBrowserEngine is true only for webview-only kinds', () {
      expect(allManga.blocking!.onlyBrowserEngine, isTrue);
      expect(const BlockingMetric().onlyBrowserEngine, isFalse);
      expect(
        const BlockingMetric(kinds: ['webview', 'captcha']).onlyBrowserEngine,
        isFalse,
      );
    });

    test('kind and blocking metric read in words', () {
      expect(describeBlockingKind('webview'), 'needs a browser engine');
      expect(blockingText(allManga.blocking), '6 % (needs a browser engine)');
    });

    test('Blocking metric is informational for webview-only', () {
      final e = {for (final m in explainMetrics(allManga)) m.title: m};
      expect(e['Blocking']!.status, MetricStatus.info);
      expect(e['Blocking']!.threshold, contains('browser engine'));
    });

    test('a real challenge next to webview still fails the metric', () {
      const mixed = SourceHealthRecord(
        id: 'm',
        name: 'm',
        blocking: BlockingMetric(
          challengeRate: 0.1,
          kinds: ['webview', 'cloudflare'],
        ),
      );
      final e = {for (final m in explainMetrics(mixed)) m.title: m};
      expect(e['Blocking']!.status, MetricStatus.fail);
    });
  });

  group('browse summary', () {
    test('carries the flag from the feed and compares by it', () async {
      final lookup = FeedSourceHealthLookup(
        FixtureSourceHealthFeed([allManga.toJson()]),
      );
      final map = await lookup.watch().first;
      expect(
        map[allManga.id],
        const SourceHealthSummary(
          verdict: HealthVerdict.keep,
          rank: 2,
          needsBrowserEngine: true,
        ),
      );
      expect(
        map[allManga.id],
        isNot(const SourceHealthSummary(verdict: HealthVerdict.keep, rank: 2)),
      );
      expect(map[allManga.id].toString(), contains('needsBrowserEngine: true'));
      expect(
        map[allManga.id].hashCode,
        isNot(
          const SourceHealthSummary(
            verdict: HealthVerdict.keep,
            rank: 2,
          ).hashCode,
        ),
      );
    });
  });
}
