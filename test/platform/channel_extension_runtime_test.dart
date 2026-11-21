import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/extension_runtime.dart';
import 'package:kartka/platform/io/channel_extension_runtime.dart';
import 'package:kartka/platform/memory/memory_extension_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kartka/ext');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('passes calls through and maps host errors', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'boom') {
        throw PlatformException(code: 'ext_error', message: 'site down');
      }
      if (call.method == 'bare') throw PlatformException(code: 'only_code');
      if (call.method == 'image') return Uint8List.fromList([7]);
      return {'ok': true};
    });
    const runtime = ChannelExtensionRuntime();
    expect(await runtime.invoke('installed'), {'ok': true});
    expect(
      await runtime.image('5', index: 2, url: '/p', imageUrl: 'https://i'),
      [7],
    );
    expect(calls[1].arguments, {
      'id': '5',
      'index': 2,
      'url': '/p',
      'imageUrl': 'https://i',
    });
    await expectLater(
      runtime.invoke('boom'),
      throwsA(
        isA<ExtensionRuntimeException>().having(
          (e) => '$e',
          'message',
          'site down',
        ),
      ),
    );
    await expectLater(
      runtime.invoke('bare'),
      throwsA(isA<ExtensionRuntimeException>()),
    );
  });

  test('image URLs round-trip through loadExtImage', () async {
    final url = extImageUrl('42', index: 3, url: '/p/3', imageUrl: 'https://x');
    final plain = extImageUrl('42', index: 0);
    expect(Uri.parse(plain).queryParameters.containsKey('img'), isFalse);
    final fake = FakeExtensionRuntime(
      images: {
        'https://x': Uint8List.fromList([1]),
      },
    );
    expect(await loadExtImage(fake, Uri.parse(url)), [1]);
    expect(fake.calls.single.$2, {'id': '42', 'index': 3, 'url': '/p/3'});
    final bare = Uri.parse('kartka-ext://source/42');
    await expectLater(
      loadExtImage(fake, bare),
      throwsA(isA<ExtensionRuntimeException>()),
    );
    expect(await fake.invoke('popular'), isNull);
    expect(await fake.invoke('init'), isA<Map<Object?, Object?>>());
  });
}
