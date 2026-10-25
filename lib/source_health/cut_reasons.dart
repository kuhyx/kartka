/// §5 cut-reason codes in plain words, using the record's own numbers.
library;

import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/thresholds.dart';

/// Resolves a source id to a display name; null when unknown.
typedef SourceNameOf = String? Function(String sourceId);

/// One sentence per entry of [record]'s `cutReasons`, in order.
///
/// [nameOf] names the covering source of a `subset` reason; without it the
/// raw source id is shown.
List<String> explainCutReasons(
  SourceHealthRecord record, {
  SourceNameOf? nameOf,
}) => [for (final code in record.cutReasons) _explain(code, record, nameOf)];

/// True when [record] was kept on score despite reasons, so they are
/// warnings rather than why the score is low.
bool keptDespiteReasons(SourceHealthRecord record) =>
    record.verdict == HealthVerdict.keep && record.cutReasons.isNotEmpty;

/// Heading over the reasons of any other record: reasons explain a low
/// score (and cut only through the profile's cut switches).
const String lowScoreHeading = 'Why the score is low';

/// Heading over the reasons of a [keptDespiteReasons] record, under a profile
/// that keeps at [keepScore] (the DEFAULT bar unless given).
String keptDespiteHeading([double keepScore = kDefaultKeepScore]) =>
    'Kept on score ≥ ${keepScore.toStringAsFixed(2)} despite';

/// A §5 blocking kind in words.
String describeBlockingKind(String kind) => switch (kind) {
  'cloudflare' => 'Cloudflare challenge',
  'captcha' => 'captcha',
  '403' => '403 Forbidden',
  '429' => '429 Too Many Requests',
  'webview' => 'needs a browser engine',
  _ => kind,
};

String _explain(String code, SourceHealthRecord r, SourceNameOf? nameOf) {
  if (code.startsWith('uptime')) return _uptime(r);
  if (code.startsWith('blocking')) return _blocking(r);
  if (code.startsWith('coverage')) return _coverage(r);
  if (code.startsWith('subset')) return _subset(r, nameOf);
  return 'Other reason: $code';
}

String _uptime(SourceHealthRecord r) {
  final need = pct(HealthThresholds.minUptimeRatio);
  final u = r.uptime;
  final ratio = u?.ratio;
  if (u == null || u.ok == null || u.probes == null || ratio == null) {
    return 'Down too often: answered fewer than $need of uptime probes.';
  }
  return 'Down too often: answered ${u.ok} of ${u.probes} uptime probes '
      '(${pct(ratio)}); at least $need is needed.';
}

String _blocking(SourceHealthRecord r) {
  final b = r.blocking;
  final kinds = b == null || b.kinds.isEmpty
      ? 'a challenge'
      : b.kinds.map(describeBlockingKind).join(', ');
  final rate = b?.challengeRate;
  final share = rate == null ? '' : ' on ${pct(rate)} of requests';
  return 'Blocks automated reading: answered with $kinds$share. '
      'Kartka never bypasses challenges, so any blocking other than a '
      'browser-engine need lowers the score.';
}

String _coverage(SourceHealthRecord r) {
  final need = pct(HealthThresholds.minCoverageRatio);
  final c = r.coverage;
  if (c == null || c.found == null || c.referenceSize == null) {
    return 'Catalogue too small: has fewer than $need of the reference titles.';
  }
  final have = c.ratio == null ? '' : ' (${pctOrDash(c.ratio)})';
  return 'Catalogue too small: has ${c.found} of ${c.referenceSize} '
      'reference titles$have; at least $need is needed.';
}

String _subset(SourceHealthRecord r, SourceNameOf? nameOf) {
  final s = r.subsetOf;
  if (s == null) {
    return 'Redundant: a higher-ranked source has nearly all of these titles '
        'with images at least as good — use another source instead.';
  }
  final other = nameOf?.call(s.sourceId) ?? s.sourceId;
  final overlap = s.overlap == null
      ? 'at least ${pct(HealthThresholds.subsetOverlap)}'
      : pct(s.overlap!);
  return 'Redundant: $overlap of its titles are also on $other, which ranks '
      'higher with images at least as good.';
}
