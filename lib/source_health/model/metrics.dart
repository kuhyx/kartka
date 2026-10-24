/// The per-metric blocks of a §5 source-health record. Every field is
/// optional: a block the evaluator has not measured yet reads as null.
library;

import 'package:flutter/foundation.dart';
import 'package:kartka/source_health/model/json_read.dart';

export 'package:kartka/source_health/model/quality_metrics.dart';

/// Whether the uptime window has filled (§5 `uptime.status`).
enum UptimeStatus {
  /// Fewer probes than a full window; uptime cannot cut the source yet.
  accruing('accruing'),

  /// A full window of probes; the uptime cut rule applies.
  finalized('final');

  const UptimeStatus(this.wire);

  /// The JSON value.
  final String wire;
}

/// §5 `uptime`: probes answered over a rolling window.
@immutable
class UptimeMetric {
  /// Creates an uptime block.
  const UptimeMetric({
    this.windowDays,
    this.probes,
    this.ok,
    this.ratio,
    this.status = UptimeStatus.accruing,
  });

  /// Parses `uptime`; null unless [json] is a map.
  static UptimeMetric? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    return UptimeMetric(
      windowDays: readInt(m, 'windowDays'),
      probes: readInt(m, 'probes'),
      ok: readInt(m, 'ok'),
      ratio: readDouble(m, 'ratio'),
      status: m['status'] == UptimeStatus.finalized.wire
          ? UptimeStatus.finalized
          : UptimeStatus.accruing,
    );
  }

  /// Window length in days.
  final int? windowDays;

  /// Probes sent in the window.
  final int? probes;

  /// Probes that got a healthy answer.
  final int? ok;

  /// ok / probes.
  final double? ratio;

  /// Accruing until the window is full.
  final UptimeStatus status;

  /// The JSON block.
  Map<String, Object?> toJson() => compact({
    'windowDays': windowDays,
    'probes': probes,
    'ok': ok,
    'ratio': ratio,
    'status': status.wire,
  });

  @override
  bool operator ==(Object other) =>
      other is UptimeMetric &&
      other.windowDays == windowDays &&
      other.probes == probes &&
      other.ok == ok &&
      other.ratio == ratio &&
      other.status == status;

  @override
  int get hashCode => Object.hash(windowDays, probes, ok, ratio, status);
}

/// §5 `latencyMs`: response-time percentiles in milliseconds.
@immutable
class LatencyMetric {
  /// Creates a latency block.
  const LatencyMetric({this.p50, this.p95});

  /// Parses `latencyMs`; null unless [json] is a map.
  static LatencyMetric? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    return LatencyMetric(p50: readInt(m, 'p50'), p95: readInt(m, 'p95'));
  }

  /// Median latency.
  final int? p50;

  /// 95th-percentile latency.
  final int? p95;

  /// The JSON block.
  Map<String, Object?> toJson() => compact({'p50': p50, 'p95': p95});

  @override
  bool operator ==(Object other) =>
      other is LatencyMetric && other.p50 == p50 && other.p95 == p95;

  @override
  int get hashCode => Object.hash(p50, p95);
}

/// §5 `blocking`: how often requests met a challenge, and which kinds.
@immutable
class BlockingMetric {
  /// Creates a blocking block.
  const BlockingMetric({this.challengeRate, this.kinds = const []});

  /// Parses `blocking`; null unless [json] is a map.
  static BlockingMetric? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    return BlockingMetric(
      challengeRate: readDouble(m, 'challengeRate'),
      kinds: readStrings(m, 'kinds'),
    );
  }

  /// Share of requests that hit a challenge (0 = never).
  final double? challengeRate;

  /// Challenge kinds seen: `cloudflare`, `captcha`, `403`, `429`.
  final List<String> kinds;

  /// The JSON block.
  Map<String, Object?> toJson() =>
      compact({'challengeRate': challengeRate, 'kinds': kinds});

  @override
  bool operator ==(Object other) =>
      other is BlockingMetric &&
      other.challengeRate == challengeRate &&
      listEquals(other.kinds, kinds);

  @override
  int get hashCode => Object.hash(challengeRate, Object.hashAll(kinds));
}

/// §5 `coverage`: reference titles the source has.
@immutable
class CoverageMetric {
  /// Creates a coverage block.
  const CoverageMetric({this.referenceSize, this.found, this.ratio});

  /// Parses `coverage`; null unless [json] is a map.
  static CoverageMetric? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    return CoverageMetric(
      referenceSize: readInt(m, 'referenceSize'),
      found: readInt(m, 'found'),
      ratio: readDouble(m, 'ratio'),
    );
  }

  /// Titles in the reference set.
  final int? referenceSize;

  /// Reference titles found on this source.
  final int? found;

  /// found / referenceSize.
  final double? ratio;

  /// The JSON block.
  Map<String, Object?> toJson() =>
      compact({'referenceSize': referenceSize, 'found': found, 'ratio': ratio});

  @override
  bool operator ==(Object other) =>
      other is CoverageMetric &&
      other.referenceSize == referenceSize &&
      other.found == found &&
      other.ratio == ratio;

  @override
  int get hashCode => Object.hash(referenceSize, found, ratio);
}
