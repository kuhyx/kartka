import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/data/source_lookup.dart';
import 'package:kartka/reader/platform/reader_system.dart';
import 'package:kartka/reader/state/reader_deps.dart';
import 'package:kartka/reader/ui/reader_screen.dart';
import 'package:kartka/reader/ui/reader_settings_tile.dart';

/// The reader part: the `/read/...` route and its settings tile.
///
/// [system] is injectable for tests; the app uses the host platform's.
KartkaFeature readerFeature(KartkaEnv env, {ReaderSystem? system}) =>
    KartkaFeature(
      id: 'reader',
      routes: [
        GoRoute(
          path: readRoutePattern,
          builder: (context, state) => _route(
            context,
            env,
            state,
            system ?? PlatformReaderSystem.host(),
          ),
        ),
      ],
      settingsTiles: [
        (context) => ReaderSettingsTile(prefs: ReaderPrefs(env.platform.kv)),
      ],
    );

/// Wires the reader to the registry. Read at route build time because the
/// registry (and therefore every service) is late in [KartkaEnv].
ReaderDeps readerDeps(KartkaEnv env) {
  final registry = env.registry;
  final platform = env.platform;
  final images = PageImageLoader(
    http: platform.http,
    blobs: platform.blobs,
    imageHeaders: registry.all<ImageHeaders>(),
  );
  return ReaderDeps(
    findSource: (id) => findSource(registry.all<SourceProvider>(), id),
    progress: registry.maybe<LibraryRepositories>()?.progress,
    downloads: registry.maybe<DownloadRepository>(),
    prefs: ReaderPrefs(platform.kv),
    loadImage: images.load,
  );
}

Widget _route(
  BuildContext context,
  KartkaEnv env,
  GoRouterState state,
  ReaderSystem system,
) {
  final args = parseReadRoute(state.uri.toString());
  if (args == null) {
    return const Scaffold(body: Center(child: Text('Unknown chapter link.')));
  }
  return ReaderScreen(
    key: ValueKey(state.uri.toString()),
    sourceId: args.sourceId,
    mangaUrl: args.mangaUrl,
    chapterUrl: args.chapterUrl,
    deps: readerDeps(env),
    system: system,
    onOpenChapter: (c) => GoRouter.of(
      context,
    ).replace<void>(readRoute(args.sourceId, args.mangaUrl, c.url)),
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
