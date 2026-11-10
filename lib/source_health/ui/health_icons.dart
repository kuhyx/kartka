import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/reason_filter.dart';

/// The glyphs of the Sources screens (textgate: no painted words). One map
/// per kind, so a metric reads the same on the card, the detail page and
/// the scoring page; each glyph is spoken with its old English name.
const Map<String, IconData> metricIcons = {
  'Uptime': Icons.monitor_heart_outlined,
  'Latency': Icons.speed,
  'Speed (latency)': Icons.speed,
  'Blocking': Icons.block,
  'Coverage': Icons.library_books_outlined,
  'Coverage (with complete chapters)': Icons.library_books_outlined,
  'Chapter completeness': Icons.format_list_numbered,
  'Chapters': Icons.format_list_numbered,
  'Image quality': Icons.image_outlined,
  'Image width': Icons.photo_size_select_large,
  'JPEG': Icons.high_quality_outlined,
  'Subset of another source': Icons.call_split,
  'Available as': Icons.extension_outlined,
  'Pages load': Icons.auto_stories_outlined,
};

/// The glyph of the metric named [label] (a key of [metricIcons]).
IconData metricIcon(String label) =>
    metricIcons[label] ?? Icons.analytics_outlined;

/// The glyph of a verdict: keep = check, cut = cross, pending = hourglass.
IconData verdictIcon(HealthVerdict v) => switch (v) {
  HealthVerdict.keep => Icons.check_circle_outline,
  HealthVerdict.cut => Icons.cancel_outlined,
  HealthVerdict.pending => Icons.hourglass_empty,
};

/// The glyph of a [HealthReason] filter / cut switch.
IconData reasonIcon(HealthReason r) => switch (r) {
  HealthReason.blocking => Icons.block,
  HealthReason.subset => Icons.call_split,
  HealthReason.coverage => Icons.library_books_outlined,
  HealthReason.uptime => Icons.monitor_heart_outlined,
  HealthReason.browserEngine => Icons.web_outlined,
  HealthReason.pagesNeverLoad => Icons.broken_image_outlined,
};

/// The glyph of a §5 cut-reason code (`uptime<0.90`, `unreachable`, ...).
IconData cutCodeIcon(String code) => switch (code) {
  'unreachable' => Icons.cloud_off_outlined,
  _ when code.startsWith('uptime') => Icons.monitor_heart_outlined,
  _ when code.startsWith('blocking') => Icons.block,
  _ when code.startsWith('coverage') => Icons.library_books_outlined,
  _ when code.startsWith('subset') => Icons.call_split,
  _ => Icons.help_outline,
};

/// The glyph of a §5 origin (`native`, `suwayomi`, `plugin`, `local`).
IconData originIcon(String origin) => switch (origin) {
  'native' => Icons.inventory_2_outlined,
  'suwayomi' => Icons.dns_outlined,
  'plugin' => Icons.extension_outlined,
  'local' => Icons.folder_outlined,
  _ => Icons.help_outline,
};

/// A small glyph spoken as [semanticLabel], then [value] (numbers, names).
class IconValue extends StatelessWidget {
  /// Draws [icon] before [value].
  const new(
    this.icon,
    this.value, {
    required this.semanticLabel,
    this.color,
    super.key,
  });

  /// The glyph naming the value.
  final IconData icon;

  /// The painted value: numbers, units or data, never words.
  final String value;

  /// The old label, for screen readers only.
  final String semanticLabel;

  /// Glyph colour; muted when null.
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: AppSpacing.xs,
    children: [
      Icon(
        icon,
        size: AppTextSize.body + 2,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        semanticLabel: semanticLabel,
      ),
      Flexible(child: Text(value)),
    ],
  );
}
