import 'package:kartka/app/feature.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/sources/suwayomi/suwayomi_feature_builder.dart';

export 'package:kartka/sources/suwayomi/suwayomi_feature_builder.dart';

/// Registry entry: the Suwayomi part, with unseen manga looked up by their
/// library title (read lazily, the registry is complete by then).
KartkaFeature suwayomiFeature(KartkaEnv env) => buildSuwayomiFeature(
  env,
  titleOf: (key) =>
      libraryTitle(env.registry.maybe<LibraryRepositories>(), key),
);

/// The library title for [key], if the manga is in the library.
Future<String?> libraryTitle(LibraryRepositories? repos, MangaKey key) async {
  if (repos == null) return null;
  final entries = await repos.library.watch().first;
  for (final entry in entries) {
    if (entry.key == key) return entry.title;
  }
  return null;
}
