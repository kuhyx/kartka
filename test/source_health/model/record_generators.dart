import 'package:glados/glados.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/model/metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// Glados generators for §5 records. Doubles stay finite (JSON has no NaN)
/// and timestamps are UTC with millisecond precision (ISO-8601 resolution).
extension HealthGenerators on Any {
  Generator<double?> get _ratio => doubleInRange(0, 1).nullable;
  Generator<int?> get _count => intInRange(0, 5000).nullable;

  Generator<UptimeMetric> get uptime => combine5(
    _count,
    _count,
    _count,
    _ratio,
    choose(UptimeStatus.values),
    (int? w, int? p, int? ok, double? r, UptimeStatus s) => UptimeMetric(
      windowDays: w,
      probes: p,
      ok: ok,
      ratio: r,
      status: s,
    ),
  );

  Generator<LatencyMetric> get latency => combine2(
    _count,
    _count,
    (int? a, int? b) => LatencyMetric(p50: a, p95: b),
  );

  Generator<BlockingMetric> get blocking => combine2(
    _ratio,
    list(choose(['cloudflare', 'captcha', '403', '429', 'other'])),
    (double? r, List<String> k) => BlockingMetric(challengeRate: r, kinds: k),
  );

  Generator<CoverageMetric> get coverage => combine3(
    _count,
    _count,
    _ratio,
    (int? s, int? f, double? r) =>
        CoverageMetric(referenceSize: s, found: f, ratio: r),
  );

  Generator<CompletenessMetric> get completeness => combine2(
    _count,
    _ratio,
    (int? s, double? r) => CompletenessMetric(sampled: s, medianRatio: r),
  );

  Generator<ImageQualityMetric> get imageQuality => combine3(
    _count,
    _count,
    _count,
    (int? s, int? w, int? q) => ImageQualityMetric(
      sampledPages: s,
      medianWidthPx: w,
      medianJpegQuality: q,
    ),
  );

  Generator<SubsetOfMetric> get subsetOf => combine2(
    nonEmptyLetterOrDigits,
    _ratio,
    (String id, double? o) => SubsetOfMetric(sourceId: id, overlap: o),
  );

  Generator<AvailabilityMetric> get availability => combine3(
    this.bool.nullable,
    this.bool.nullable,
    this.bool.nullable,
    (bool? n, bool? j, bool? k) =>
        AvailabilityMetric(native: n, mangayomiJs: j, keiyoushi: k),
  );

  Generator<DateTime?> get _instant => intInRange(0, 4102444800000)
      .map((ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true))
      .nullable;

  Generator<SourceHealthRecord> get _identity => combine5(
    nonEmptyLetterOrDigits,
    letterOrDigits,
    letterOrDigits,
    choose(['native', 'suwayomi', 'plugin', 'local', 'odd']),
    _instant,
    (String id, String name, String lang, String origin, DateTime? at) =>
        SourceHealthRecord(
          id: id,
          name: name.isEmpty ? id : name,
          lang: lang,
          origin: origin,
          probedAt: at,
        ),
  );

  Generator<SourceHealthRecord> get healthRecord => combine10(
    _identity,
    uptime.nullable,
    latency.nullable,
    blocking.nullable,
    coverage.nullable,
    completeness.nullable,
    imageQuality.nullable,
    subsetOf.nullable,
    combine3(
      _ratio,
      intInRange(1, 400).nullable,
      availability.nullable,
      (double? s, int? r, AvailabilityMetric? a) => (s, r, a),
    ),
    combine2(
      choose(HealthVerdict.values),
      list(choose(['uptime<0.95', 'blocking', 'coverage<0.60', 'subset'])),
      (HealthVerdict v, List<String> c) => (v, c),
    ),
    (
      SourceHealthRecord base,
      UptimeMetric? u,
      LatencyMetric? l,
      BlockingMetric? b,
      CoverageMetric? c,
      CompletenessMetric? cc,
      ImageQualityMetric? iq,
      SubsetOfMetric? so,
      (double?, int?, AvailabilityMetric?) ranking,
      (HealthVerdict, List<String>) verdict,
    ) => SourceHealthRecord(
      id: base.id,
      name: base.name,
      lang: base.lang,
      origin: base.origin,
      probedAt: base.probedAt,
      uptime: u,
      latency: l,
      blocking: b,
      coverage: c,
      completeness: cc,
      imageQuality: iq,
      subsetOf: so,
      availability: ranking.$3,
      score: ranking.$1,
      rank: ranking.$2,
      verdict: verdict.$1,
      cutReasons: verdict.$2,
    ),
  );
}
