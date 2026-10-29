import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/platform/platform.dart';

/// The bottom-navigation tabs of the app shell, in display order (the
/// router builds one branch per value, in this order).
enum KartkaTab {
  /// Saved manga and categories.
  library,

  /// New chapters found in library manga.
  updates,

  /// Search and browse sources.
  browse,

  /// Source health ranking.
  sources,

  /// Settings, imports, about.
  more,
}

/// What one part contributes to the app (DOCS-contracts §3, §10).
///
/// Every field defaults to empty, so a part fills in only what it has.
class KartkaFeature {
  /// Creates a feature.
  const new({
    required this.id,
    this.routes = const [],
    this.tabs = const {},
    this.settingsTiles = const [],
    this.services = const [],
  });

  /// Unique part id, e.g. `library`, `source-mangadex`.
  final String id;

  /// Top-level go_router routes (paths from `lib/app/routes.dart` where one
  /// exists there).
  final List<RouteBase> routes;

  /// Body for a shell tab. The first feature in registry order that fills a
  /// tab wins; a tab nobody fills shows a placeholder.
  final Map<KartkaTab, WidgetBuilder> tabs;

  /// Tiles shown on the More tab, in registry order.
  final List<WidgetBuilder> settingsTiles;

  /// Port implementations and services, looked up by type through
  /// `KartkaRegistry.all` / `KartkaRegistry.maybe`. Ports are declared in the
  /// consumer's directory; this file never imports feature directories.
  /// Sources arrive only this way, as `SourceProvider`s.
  final List<Object> services;
}

/// What a feature factory gets to build its [KartkaFeature] from.
class KartkaEnv {
  /// Creates an environment over [platform].
  new(this.platform);

  /// Platform services (HTTP, storage, file picking, OAuth).
  final KartkaPlatform platform;

  /// The finished registry. Only valid after every factory has run, so read
  /// it lazily (inside a service method or widget), never while building.
  late final KartkaRegistry registry;
}

/// Builds one part's feature. Parts export one of these and append it to
/// `kartkaFeatureFactories` in `lib/app/registry.dart`.
typedef KartkaFeatureFactory = KartkaFeature Function(KartkaEnv env);

/// Every feature, in registry order, with typed service lookup.
class KartkaRegistry {
  /// Creates a registry over [features] (registry order).
  new(List<KartkaFeature> features) : features = List.unmodifiable(features);

  /// Runs [factories] in order against [platform] and wires the result.
  factory build(KartkaPlatform platform, List<KartkaFeatureFactory> factories) {
    final env = KartkaEnv(platform);
    final registry = KartkaRegistry([for (final f in factories) f(env)]);
    env.registry = registry;
    return registry;
  }

  /// Features in registry order.
  final List<KartkaFeature> features;

  /// Every service of type [T], in registry order.
  List<T> all<T extends Object>() => [
    for (final f in features) ...f.services.whereType<T>(),
  ];

  /// The first service of type [T], or `null`.
  T? maybe<T extends Object>() {
    for (final f in features) {
      for (final s in f.services) {
        if (s is T) return s;
      }
    }
    return null;
  }

  /// Every route, in registry order.
  List<RouteBase> get routes => [for (final f in features) ...f.routes];

  /// Every settings tile, in registry order.
  List<WidgetBuilder> get settingsTiles => [
    for (final f in features) ...f.settingsTiles,
  ];

  /// The body for [tab], or `null` when no feature fills it.
  WidgetBuilder? tab(KartkaTab tab) {
    for (final f in features) {
      final builder = f.tabs[tab];
      if (builder != null) return builder;
    }
    return null;
  }
}
