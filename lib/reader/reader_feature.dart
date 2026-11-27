import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/app/settings_stores.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/reader/data/page_image_warmer.dart';
import 'package:kartka/reader/data/page_list_cache.dart';
import 'package:kartka/reader/data/page_warm_slot.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/data/source_lookup.dart';
import 'package:kartka/reader/logic/shown_page_wait.dart';
import 'package:kartka/reader/platform/reader_system.dart';
import 'package:kartka/reader/state/reader_deps.dart';
import 'package:kartka/reader/ui/reader_screen.dart';
import 'package:kartka/reader/ui/reader_settings_tile.dart';
import 'package:material_ui/material_ui.dart';

/// The reader part: the `/read/...` route and its settings tile.
///
/// [system] is injectable for tests; the app uses the host platform's.
KartkaFeature readerFeature(KartkaEnv env, {ReaderSystem? system}) {
  // One per app run: a route's deps are rebuilt on every open.
  final pageLists = PageListCache(env.platform.kv);
  // The registry is late: the loader is built when an image is fetched.
  final images = PageImageWarmer((page) => _imageLoader(env).load(page));
  // One per app run too: it keeps every provider's list between opens.
  final sources = SourceLookup(() => env.registry.all<SourceProvider>());
  // One per app run: downloads wait on it through the registry.
  final shown = ShownPageWait(
    onStart: () => unawaited(env.platform.extensions?.cancelBackground()),
  );
  return KartkaFeature(
    id: 'reader',
    services: [
      shown,
      PageWarmSlot(
        cache: pageLists,
        findSource: sources.find,
        progress: () => env.registry.maybe<LibraryRepositories>()?.progress,
        downloads: () => env.registry.maybe<DownloadRepository>(),
        images: images,
      ),
    ],
    routes: [
      GoRoute(
        path: readRoutePattern,
        builder: (context, state) => _route(
          context,
          env,
          state,
          system ?? PlatformReaderSystem.host(),
          pageLists,
          images,
          sources,
          shown,
        ),
      ),
    ],
    settingsTiles: [
      (context) => ReaderSettingsTile(prefs: ReaderPrefs(syncedKv(env))),
    ],
  );
}

/// Route `extra` that opens the chapter on its last page (a JSON value, so
/// the web build's history state can hold it).
const readAtEndExtra = 'kartka.reader.atEnd';

/// Wires the reader to the registry. Read at route build time because the
/// registry (and therefore every service) is late in [KartkaEnv].
ReaderDeps readerDeps(
  KartkaEnv env, {
  PageListCache? pageLists,
  PageImageWarmer? images,
  SourceLookup? sources,
  ShownPageWait? shown,
}) {
  final registry = env.registry;
  final platform = env.platform;
  return ReaderDeps(
    findSource: (sources ?? SourceLookup(registry.all<SourceProvider>)).find,
    progress: registry.maybe<LibraryRepositories>()?.progress,
    downloads: registry.maybe<DownloadRepository>(),
    // The global settings sync (§16); per-manga modes are never listed.
    prefs: ReaderPrefs(syncedKv(env)),
    loadImage: images?.load ?? _imageLoader(env).load,
    diagnostics: DiagnosticsLog.of(platform.diagnostics),
    pageLists: pageLists,
    storedChapters: registry.maybe<StoredChapterLists>(),
    imageStarted: images?.started,
    shownPages: shown,
  );
}

Widget _route(
  BuildContext context,
  KartkaEnv env,
  GoRouterState state,
  ReaderSystem system,
  PageListCache pageLists,
  PageImageWarmer images,
  SourceLookup sources,
  ShownPageWait shown,
) {
  final args = parseReadRoute(state.uri.toString());
  if (args == null) {
    return const Scaffold(
      body: EmptyMark(
        icon: Icons.link_off,
        semanticLabel: 'Unknown chapter link.',
      ),
    );
  }
  return ReaderScreen(
    key: ValueKey(state.uri.toString()),
    sourceId: args.sourceId,
    mangaUrl: args.mangaUrl,
    chapterUrl: args.chapterUrl,
    deps: readerDeps(
      env,
      pageLists: pageLists,
      images: images,
      sources: sources,
      shown: shown,
    ),
    system: system,
    startAtEnd: state.extra == readAtEndExtra,
    onOpenChapter: (c, {atEnd = false}) => GoRouter.of(context).replace<void>(
      readRoute(args.sourceId, args.mangaUrl, c.url),
      extra: atEnd ? readAtEndExtra : null,
    ),
    onExit: () {
      final router = GoRouter.of(context);
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(mangaRoute(args.sourceId, args.mangaUrl));
      }
    },
  );
}

/// Page images: offline blobs or the network, with the image headers.
PageImageLoader _imageLoader(KartkaEnv env) => PageImageLoader(
  http: env.platform.http,
  blobs: env.platform.blobs,
  imageHeaders: env.registry.all<ImageHeaders>(),
  extensions: env.platform.extensions,
);
