import 'package:kartka/app/feature.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/updates/data/update_feed.dart';
import 'package:kartka/updates/state/library_keys.dart';
import 'package:kartka/updates/state/update_runner.dart';
import 'package:kartka/updates/state/updates_deps.dart';
import 'package:kartka/updates/ui/updates_screen.dart';

/// The updates part: the Updates tab, the feed (a `ChapterAdditionSink`
/// browse's chapter store reports into) and the shared "update all" run
/// (`LibraryUpdater`, which the Library tab picks up too).
KartkaFeature updatesFeature(KartkaEnv env) {
  // Read lazily: the registry is complete only after every factory ran.
  LibraryRepositories repos() =>
      env.registry.maybe<LibraryRepositories>() ??
      (throw StateError('updates needs the library feature registered'));
  final keys = LibraryKeys(() => repos().library.watch());
  final feed = UpdateFeed(env.platform.kv, inLibrary: keys.contains);
  final runner = UpdateRunner(
    libraryKeys: keys.current,
    check: (key) =>
        (env.registry.maybe<ChapterUpdateChecker>() ??
                (throw StateError('updates needs a ChapterUpdateChecker')))
            .check(key),
    diagnostics: DiagnosticsLog.of(env.platform.diagnostics),
  );
  UpdatesDeps? deps;
  UpdatesDeps build() {
    final images = PageImageLoader(
      http: env.platform.http,
      blobs: env.platform.blobs,
      imageHeaders: env.registry.all<ImageHeaders>(),
    );
    return UpdatesDeps(
      feed: feed,
      library: repos().library,
      progress: repos().progress,
      updater: runner,
      coverLoader: (url) => images.load(PageRef(index: 0, imageUrl: url)),
    );
  }

  UpdatesDeps resolve() => deps ??= build();
  return KartkaFeature(
    id: 'updates',
    tabs: {KartkaTab.updates: (_) => UpdatesScreen(deps: resolve())},
    services: [feed, runner],
  );
}
