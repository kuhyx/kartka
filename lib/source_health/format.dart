/// Display formatting shared by the explanations and the UI.
library;

/// Placeholder for a metric the evaluator has not measured.
const String notMeasured = '—';

/// [ratio] (0..1) as a whole percentage, e.g. `96 %`.
String pct(double ratio) => '${(ratio * 100).round()} %';

/// [ratio] as a percentage, or [notMeasured].
String pctOrDash(double? ratio) => ratio == null ? notMeasured : pct(ratio);

/// Milliseconds as `420 ms` or, from one second up, `1.3 s`.
String millis(int? ms) {
  if (ms == null) return notMeasured;
  return ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';
}

/// [value] with [unit], or [notMeasured].
String withUnit(int? value, String unit) =>
    value == null ? notMeasured : '$value$unit';

/// A UTC instant as `2026-10-24 12:00 UTC`.
String instant(DateTime at) {
  final u = at.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)} '
      '${two(u.hour)}:${two(u.minute)} UTC';
}
