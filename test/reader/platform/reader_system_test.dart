import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/platform/reader_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
  });

  test('keeps the screen awake only on Android', () async {
    final wake = <bool>[];
    final android = PlatformReaderSystem(
      isAndroid: true,
      isWeb: false,
      wakelock: ({required on}) async => wake.add(on),
    );
    await android.keepAwake(on: true);
    await android.keepAwake(on: false);
    expect(wake, [true, false]);

    final desktop = PlatformReaderSystem(
      isAndroid: false,
      isWeb: true,
      wakelock: ({required on}) async => wake.add(on),
    );
    await desktop.keepAwake(on: true);
    expect(wake, [true, false]);
  });

  test('Android fullscreen hides and restores the system bars', () async {
    final system = PlatformReaderSystem(
      isAndroid: true,
      isWeb: false,
      wakelock: ({required on}) async {},
    );
    await system.setFullscreen(on: true);
    await system.setFullscreen(on: false);
    final modes = [
      for (final c in calls)
        if (c.method == 'SystemChrome.setEnabledSystemUIMode') c.arguments,
    ];
    expect(modes, [
      'SystemUiMode.immersiveSticky',
      'SystemUiMode.edgeToEdge',
    ]);
  });

  test('web fullscreen goes through the browser hook', () async {
    final requests = <bool>[];
    final system = PlatformReaderSystem(
      isAndroid: false,
      isWeb: true,
      wakelock: ({required on}) async {},
      browserFullscreen: ({required on}) async => requests.add(on),
    );
    await system.setFullscreen(on: true);
    await system.setFullscreen(on: false);
    expect(requests, [true, false]);
    expect(calls, isEmpty);
  });

  test('host() reads the running platform', () {
    final system = PlatformReaderSystem.host();
    // flutter_test reports Android as the target platform on every host.
    expect(system.isAndroid, defaultTargetPlatform == TargetPlatform.android);
    expect(system.isWeb, isFalse);
  });
}
