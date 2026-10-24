/// The feature registry (DOCS-contracts §3).
///
/// APPEND-ONLY: each part adds exactly one import and one line to
/// [kartkaFeatureFactories], at the end. Parts never edit each other's lines.
library;

import 'package:kartka/app/feature.dart';
import 'package:kartka/downloads/downloads_feature.dart';
import 'package:kartka/library/library_feature.dart';
import 'package:kartka/sources/local/local_feature.dart';
import 'package:kartka/sources/mangadex/mangadex_feature.dart';
import 'package:kartka/sources/suwayomi/suwayomi_feature.dart';

export 'package:kartka/app/feature.dart';

/// Every part's feature factory, in registry order.
final List<KartkaFeatureFactory> kartkaFeatureFactories = [
  // Parts append below this line, one entry each.
  libraryFeature,
  downloadsFeature,
  mangadexFeature,
  localFeature,
  suwayomiFeature,
];
