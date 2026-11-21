import 'package:flutter/services.dart';
import 'package:kartka/platform/extension_runtime.dart';

/// [ExtensionRuntime] over the `kartka/ext` method channel (MainActivity).
class ChannelExtensionRuntime implements ExtensionRuntime {
  /// Talks to [channel]; the default is the app's.
  const new({this.channel = const MethodChannel('kartka/ext')});

  /// The host channel.
  final MethodChannel channel;

  @override
  Future<Object?> invoke(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    try {
      return await channel.invokeMethod<Object?>(method, args);
    } on PlatformException catch (e) {
      throw ExtensionRuntimeException(e.message ?? e.code);
    }
  }

  @override
  Future<Uint8List> image(
    String sourceId, {
    required int index,
    required String url,
    String? imageUrl,
  }) async =>
      (await invoke('image', {
            'id': sourceId,
            'index': index,
            'url': url,
            'imageUrl': imageUrl,
          }))!
          as Uint8List;
}
