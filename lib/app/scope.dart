import 'package:flutter/widgets.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/platform/platform.dart';

/// Gives every widget the registry and the platform services.
class KartkaScope extends InheritedWidget {
  /// Provides [registry] and [platform] to [child].
  const new({
    required this.registry,
    required this.platform,
    required super.child,
    super.key,
  });

  /// Every feature and service.
  final KartkaRegistry registry;

  /// HTTP, storage, file picking, OAuth.
  final KartkaPlatform platform;

  /// The nearest scope; throws when there is none.
  static KartkaScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KartkaScope>()!;

  @override
  bool updateShouldNotify(KartkaScope oldWidget) =>
      registry != oldWidget.registry || platform != oldWidget.platform;
}
