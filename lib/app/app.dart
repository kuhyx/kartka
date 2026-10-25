import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/scope.dart';
import 'package:kartka/app/shell.dart';
import 'package:kartka/platform/platform.dart';

export 'package:kartka/app/scope.dart';

/// Builds the router: one branch per shell tab, then every feature route.
GoRouter buildRouter(KartkaRegistry registry) => GoRouter(
  initialLocation: '/${KartkaTab.library.name}',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => KartkaShell(shell: shell),
      branches: [
        for (final tab in KartkaTab.values)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/${tab.name}',
                builder: (context, _) => _tabBody(context, registry, tab),
              ),
            ],
          ),
      ],
    ),
    ...registry.routes,
  ],
);

Widget _tabBody(BuildContext context, KartkaRegistry registry, KartkaTab tab) {
  if (tab == KartkaTab.more) {
    final filled = registry.tab(tab);
    return filled?.call(context) ?? MoreTab(tiles: registry.settingsTiles);
  }
  return registry.tab(tab)?.call(context) ?? TabPlaceholder(tab);
}

/// The Kartka app: shared theme, registry scope, router.
class KartkaApp extends StatefulWidget {
  /// Runs [registry] on [platform].
  const new({required this.registry, required this.platform, super.key});

  /// Every feature.
  final KartkaRegistry registry;

  /// Platform services.
  final KartkaPlatform platform;

  @override
  State<KartkaApp> createState() => _KartkaAppState();
}

class _KartkaAppState extends State<KartkaApp> {
  late final GoRouter _router = buildRouter(widget.registry);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KartkaScope(
    registry: widget.registry,
    platform: widget.platform,
    child: MaterialApp.router(
      title: 'Kartka',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: _router,
      // Hidden engine views (Android) mount beside the routes.
      builder: (_, child) =>
          widget.platform.browser.host(child ?? const SizedBox.shrink()),
    ),
  );
}
