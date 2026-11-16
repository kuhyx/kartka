import 'package:design_system/design_system.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';
import 'package:kartka/source_health/install/source_installs.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ranking.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/ui/filters_sheet.dart';
import 'package:kartka/source_health/ui/source_card.dart';
import 'package:material_ui/material_ui.dart';

/// Long-press sheet: the full card of source [id] (every metric, the subset
/// link, the install action). [onOpen] opens a detail page once the sheet is
/// closed.
void showSourceSheet(
  BuildContext context, {
  required List<SourceHealthRecord> all,
  required String id,
  required double keepScore,
  required OpenSource onOpen,
  SourceInstalls? installs,
}) {
  String? nameOf(String other) {
    for (final r in all) {
      if (r.id == other) return r.name;
    }
    return null;
  }

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SourceCard(
          record: all.firstWhere((r) => r.id == id),
          nameOf: nameOf,
          keepScore: keepScore,
          installs: installs,
          onOpen: (target) {
            Navigator.of(sheet).pop();
            onOpen(target);
          },
        ),
      ),
    ),
  );
}

/// The "Filters" sheet over [query]; Migrate closes it first.
void showFiltersSheet(
  BuildContext context, {
  required List<SourceHealthRecord> records,
  required SourceHealthMeta? meta,
  required ValueNotifier<HealthQuery> query,
  required DateTime now,
  ScoringProfileStore? scoring,
  KeepReconciler? autoInstall,
  void Function(BuildContext context)? onMigrate,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (sheet) => FiltersSheet(
    records: records,
    meta: meta,
    query: query,
    now: now,
    scoring: scoring,
    autoInstall: autoInstall,
    onMigrate: onMigrate == null
        ? null
        : (_) {
            Navigator.of(sheet).pop();
            onMigrate(context);
          },
  ),
);
