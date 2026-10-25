import 'package:kartka/core/source/challenge.dart';
import 'package:kartka/plugins/runtime/host_api.dart';

/// A plugin call that failed on a browser challenge
/// (docs/DOCS-contracts-webview.md §4): still a [PluginException] naming
/// the plugin, and a [ChallengeRequired] so the UI can offer the WebView.
class PluginChallengeException extends PluginException
    implements ChallengeRequired {
  /// Wraps [challenge] for [pluginId]; [message] is the plugin's error text.
  new(
    super.pluginId,
    super.message, {
    required ChallengeRequired challenge,
    super.method,
  }) : url = challenge.url,
       kind = challenge.kind;

  @override
  final Uri url;

  @override
  final String kind;
}

final _inText = RegExp(r'ChallengeRequired\(([\w-]+), (\S+?)\)');

/// The challenge named in [message] (a host error crosses the sandbox as
/// text: `ChallengeRequired(<kind>, <url>)`), or null.
PluginChallengeException? challengeFromMessage(
  String pluginId,
  String message,
  PluginMethod? method,
) {
  final m = _inText.firstMatch(message);
  final url = m == null ? null : Uri.tryParse(m.group(2)!);
  if (url == null) return null;
  return PluginChallengeException(
    pluginId,
    message,
    challenge: ChallengeRequired(url, m!.group(1)!),
    method: method,
  );
}
