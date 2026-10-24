import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// TODO(reader): swap for foundation's web fullscreen seam once it exists;
// package:web may only be imported under lib/platform/web/.
import 'package:kartka/reader/platform/browser_fullscreen_stub.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Device integration the reader needs: screen wake lock and fullscreen.
abstract interface class ReaderSystem {
  /// Keeps the screen on while [on] (Android only; a no-op elsewhere).
  Future<void> keepAwake({required bool on});

  /// Enters or leaves fullscreen.
  Future<void> setFullscreen({required bool on});
}

/// Toggles a platform capability.
typedef Toggle = Future<void> Function({required bool on});

/// [ReaderSystem] backed by wakelock_plus, SystemChrome and the browser's
/// Fullscreen API.
class PlatformReaderSystem implements ReaderSystem {
  /// A system with explicit platform flags and hooks (for tests).
  const new({
    required this.isAndroid,
    required this.isWeb,
    required this.wakelock,
    this.browserFullscreen = setBrowserFullscreen,
  });

  /// The system for the platform the app is running on.
  factory host() => PlatformReaderSystem(
    isAndroid: defaultTargetPlatform == TargetPlatform.android && !kIsWeb,
    isWeb: kIsWeb,
    wakelock: _wakelockPlus,
  );

  /// Whether this is the Android app.
  final bool isAndroid;

  /// Whether this is the web build (the desktop Chrome app).
  final bool isWeb;

  /// Enables or disables the wake lock.
  final Toggle wakelock;

  /// Requests or exits browser fullscreen.
  final Toggle browserFullscreen;

  // Plugin channel glue; behaviour is covered through the injected hook.
  // coverage:ignore-start
  static Future<void> _wakelockPlus({required bool on}) =>
      WakelockPlus.toggle(enable: on);
  // coverage:ignore-end

  @override
  Future<void> keepAwake({required bool on}) async {
    if (isAndroid) await wakelock(on: on);
  }

  @override
  Future<void> setFullscreen({required bool on}) {
    if (isWeb) return browserFullscreen(on: on);
    if (!isAndroid) return Future.value();
    return SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }
}
