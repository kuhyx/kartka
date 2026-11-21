import 'package:kartka/app/feature.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/sources/device_ext/device_ext_feature.dart';
import 'package:kartka/sources/suwayomi/suwayomi_feature_builder.dart';

export 'package:kartka/sources/suwayomi/suwayomi_feature_builder.dart';

/// Registry entry: the Suwayomi part, with unseen manga looked up by their
/// library title (read lazily, the registry is complete by then).
///
/// On Android the extensions run in the app instead
/// ([buildDeviceExtFeature]): no server URL is read or contacted there.
KartkaFeature suwayomiFeature(KartkaEnv env) {
  final runtime = env.platform.extensions;
  if (runtime != null) return buildDeviceExtFeature(env, runtime);
  return buildSuwayomiFeature(
    env,
    titleOf: (key) =>
        libraryTitle(env.registry.maybe<LibraryRepositories>(), key),
  );
}

/// The library title for [key], if the manga is in the library.
Future<String?> libraryTitle(LibraryRepositories? repos, MangaKey key) async {
  if (repos == null) return null;
  final entries = await repos.library.watch().first;
  for (final entry in entries) {
    if (entry.key == key) return entry.title;
  }
  return null;
}
