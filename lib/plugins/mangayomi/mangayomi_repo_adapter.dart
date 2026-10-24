import 'package:kartka/plugins/mangayomi/mangayomi_converter.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_entry.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_index.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';

/// Makes a Mangayomi repo `index.json` a plugin repo type: its JS manga
/// extensions are offered as Kartka plugins and converted on install.
///
/// Shaped as the runtime's `PluginRepoAdapter` port (accepts / parse /
/// buildSource) so the Plugins screen lists Mangayomi repos next to Kartka
/// ones.
class MangayomiRepoAdapter {
  /// Index entries seen by [parse], by plugin id; [buildSource] needs the
  /// full entry (`this.source`, e.g. `apiUrl`), which `PluginIndexEntry`
  /// does not carry.
  final Map<String, MangayomiEntry> _seen = {};

  /// True when [indexJson] is a Mangayomi index (a top-level array).
  bool accepts(Object? indexJson) => MangayomiIndex.looksLike(indexJson);

  /// The convertible sources of [json] as plugin offers. The JS file URL is
  /// the entry's `sourceCodeUrl`; Mangayomi indexes carry no checksum.
  List<PluginIndexEntry> parse(Object? json, Uri indexUrl) {
    final out = <PluginIndexEntry>[];
    for (final e in MangayomiIndex.parse(json)) {
      final url = indexUrl.resolve(e.sourceCodeUrl);
      if (!isHttpUrl(url)) continue;
      _seen[e.pluginId] = e;
      out.add(
        PluginIndexEntry(
          manifest: e.toManifest(),
          url: url,
          repoUrl: indexUrl.toString(),
        ),
      );
    }
    return out;
  }

  /// The Kartka plugin JS for offer [e] given its fetched extension JS.
  ///
  /// Throws [StateError] when [e] did not come from this adapter's [parse].
  Future<String> buildSource(PluginIndexEntry e, String fetchedJs) async {
    final entry = _seen[e.manifest.id];
    if (entry == null) {
      throw StateError(
        'Mangayomi plugin "${e.manifest.id}" is not in a loaded repo index',
      );
    }
    return MangayomiConverter.convert(entry, fetchedJs).source;
  }
}
