import 'package:kartka/plugins/runtime/host_api.dart';

/// Routes a JS `kartka.*` host call to [PluginHostServices].
///
/// Only the ops in contracts section 6 exist; anything else is rejected, and
/// every argument is type-checked because it comes from untrusted JS.
class HostDispatcher {
  /// Creates a dispatcher over [services].
  HostDispatcher(this.services);

  /// The Dart-side implementation.
  final PluginHostServices services;

  /// Runs [op]; the result is JSON-encodable. Throws on bad input.
  Future<Object?> dispatch(String op, List<Object?> args) async {
    switch (op) {
      case 'http.get':
        final o = _opts(args);
        return (await services.httpGet(
          _str(args, 0),
          headers: _headers(o['headers']),
        )).toJson();
      case 'http.post':
        final o = _opts(args);
        final body = o['body'];
        return (await services.httpPost(
          _str(args, 0),
          headers: _headers(o['headers']),
          body: body == null ? null : body.toString(),
        )).toJson();
      case 'html.select':
        return [
          for (final m in services.htmlSelect(_str(args, 0), _str(args, 1)))
            m.toJson(),
        ];
      case 'log':
        services.log(_str(args, 0));
        return null;
      case 'prefs.get':
        return services.prefsGet(_str(args, 0));
      case 'prefs.set':
        await services.prefsSet(_str(args, 0), _str(args, 1));
        return null;
      default:
        throw ArgumentError('unknown host operation "$op"');
    }
  }

  static String _str(List<Object?> args, int i) {
    if (i < args.length && args[i] is String) return args[i]! as String;
    throw ArgumentError('argument ${i + 1} must be a string');
  }

  static Map<String, Object?> _opts(List<Object?> args) {
    final o = args.length > 1 ? args[1] : null;
    return o is Map ? o.cast<String, Object?>() : const {};
  }

  static Map<String, String> _headers(Object? h) => h is Map
      ? {for (final e in h.entries) e.key.toString(): e.value.toString()}
      : const {};
}
