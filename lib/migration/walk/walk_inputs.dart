import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// What the migration walk reads besides the library: the scored
/// source-health records, the installed sources and the Keep
/// auto-install's flags.
class MigrationInputs {
  /// Creates the inputs; without [flagOf] no source counts as failing.
  const new({
    required this.records,
    required this.sources,
    this.meta,
    this.flagOf,
  });

  /// The source-health records under the active profile.
  final Future<List<SourceHealthRecord>> Function() records;

  /// Every installed source (after the providers settled).
  final Future<List<MangaSource>> Function() sources;

  /// The published run's meta (its `rejectedIds`); none when absent.
  final Future<SourceHealthMeta?> Function()? meta;

  /// The auto-install flag of a source id, if any.
  final String? Function(String id)? flagOf;
}
