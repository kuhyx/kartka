// Every §5 metric block is a value: equal JSON, equal object and hash. The
// record compares its JSON, so these are checked here directly.
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/model/metrics.dart';

typedef _Parse = Object? Function(Object? json);

void main() {
  final blocks = <String, (_Parse, Map<String, Object?>, Map<String, Object?>)>{
    'uptime': (
      UptimeMetric.fromJson,
      {'windowDays': 7, 'probes': 28, 'ok': 27, 'ratio': 0.964},
      {'ratio': 0.5},
    ),
    'latencyMs': (LatencyMetric.fromJson, {'p50': 1, 'p95': 2}, {'p95': 3}),
    'blocking': (
      BlockingMetric.fromJson,
      {
        'challengeRate': 0.6,
        'kinds': ['cloudflare'],
        'hardRate': 0.6,
      },
      {
        'challengeRate': 0.6,
        'kinds': ['cloudflare'],
        'hardRate': 0.5,
      },
    ),
    'coverage': (
      CoverageMetric.fromJson,
      {'referenceSize': 500, 'found': 400, 'complete': 350},
      {'referenceSize': 500, 'found': 400, 'complete': 349},
    ),
    'chapterCompleteness': (
      CompletenessMetric.fromJson,
      {'sampled': 4, 'medianRatio': 0.9},
      {'sampled': 4},
    ),
    'imageQuality': (
      ImageQualityMetric.fromJson,
      {'sampledPages': 3, 'medianWidthPx': 1067, 'medianJpegQuality': 90},
      {'medianWidthPx': 800},
    ),
    'subsetOf': (
      SubsetOfMetric.fromJson,
      {'sourceId': 'a', 'overlap': 0.62},
      {'sourceId': 'b', 'overlap': 0.62},
    ),
    'availability': (
      AvailabilityMetric.fromJson,
      {'native': false, 'mangayomiJs': false, 'keiyoushi': true},
      {'native': true},
    ),
    'pagesLoad': (
      PagesLoadMetric.fromJson,
      {'ratio': 1, 'sampled': 10},
      {'ratio': 0, 'sampled': 10},
    ),
    'plugin': (
      PluginInstallRef.fromJson,
      {'repo': 'https://r/index.json', 'id': 'mangayomi-1'},
      {'repo': 'https://r/index.json', 'id': 'mangayomi-2'},
    ),
  };

  for (final MapEntry(key: name, value: (parse, json, other))
      in blocks.entries) {
    test('$name compares by value', () {
      final a = parse(json);
      final b = parse({...json});
      expect(a, isNotNull);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(parse(other)));
    });
  }

  test('a plugin reference needs a string repo and id', () {
    expect(PluginInstallRef.fromJson(null), isNull);
    expect(PluginInstallRef.fromJson({'repo': 'r'}), isNull);
    expect(PluginInstallRef.fromJson({'id': 'i'}), isNull);
    const ref = PluginInstallRef(repo: 'r', id: 'i');
    expect(PluginInstallRef.fromJson(ref.toJson()), ref);
  });
}
