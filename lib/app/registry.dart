/// The feature registry (DOCS-contracts §3).
///
/// APPEND-ONLY: each part adds exactly one import and one line to
/// [kartkaFeatureFactories], at the end. Parts never edit each other's lines.
library;

import 'package:kartka/app/feature.dart';
import 'package:kartka/backup_import/backup_import_feature.dart';
import 'package:kartka/tracking/mal/mal_feature.dart';
import 'package:kartka/tracking/mangaupdates/mu_feature.dart';

export 'package:kartka/app/feature.dart';

/// Every part's feature factory, in registry order.
final List<KartkaFeatureFactory> kartkaFeatureFactories = [
  // Parts append below this line, one entry each.
  backupImportFeature,
  malFeature,
  mangaUpdatesFeature,
];
