/// The feature registry (DOCS-contracts §3).
///
/// APPEND-ONLY: each part adds exactly one import and one line to
/// [kartkaFeatureFactories], at the end. Parts never edit each other's lines.
library;

import 'package:kartka/app/feature.dart';
import 'package:kartka/backup_import/backup_import_feature.dart';
import 'package:kartka/browse/browse_feature.dart';
import 'package:kartka/downloads/downloads_feature.dart';
import 'package:kartka/library/library_feature.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_feature.dart';
import 'package:kartka/plugins/runtime/plugins_feature.dart';
import 'package:kartka/reader/reader_feature.dart';
import 'package:kartka/source_health/source_health_feature.dart';
import 'package:kartka/sources/local/local_feature.dart';
import 'package:kartka/sources/mangadex/mangadex_feature.dart';
import 'package:kartka/sources/suwayomi/suwayomi_feature.dart';
import 'package:kartka/sync/sync_feature.dart';
import 'package:kartka/tracking/anilist/tracking_feature.dart';
import 'package:kartka/tracking/mal/mal_feature.dart';
import 'package:kartka/tracking/mangaupdates/mu_feature.dart';

export 'package:kartka/app/feature.dart';

/// Every part's feature factory, in registry order.
final List<KartkaFeatureFactory> kartkaFeatureFactories = [
  // Parts append below this line, one entry each.
  libraryFeature,
  downloadsFeature,
  mangadexFeature,
  localFeature,
  suwayomiFeature,
  pluginsFeature,
  mangayomiFeature,
  backupImportFeature,
  trackingFeature,
  sourceHealthFeature,
  syncFeature,
  browseFeature,
  readerFeature,
  malFeature,
  mangaUpdatesFeature,
];
