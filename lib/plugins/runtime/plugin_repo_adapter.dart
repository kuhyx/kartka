import 'package:kartka/plugins/runtime/plugin_index.dart';

/// Port for repo formats other than Kartka's native `{"plugins": [...]}`.
///
/// The Mangayomi converter supplies one through `KartkaFeature.services`; the
/// plugin manager asks every adapter (registry order) and the first whose
/// [accepts] returns true parses the index. Entries it returns carry the
/// adapter, so [buildSource] runs at install time and its result (a normal
/// Kartka plugin: JS defining the six entry points) is what gets stored.
abstract interface class PluginRepoAdapter {
  /// Whether [indexJson] (the decoded `index.json`) is this adapter's format.
  bool accepts(Object? indexJson);

  /// Entries of [json] (already accepted); [indexUrl] resolves relative URLs.
  ///
  /// Each entry's `url` is the file [buildSource] will receive as
  /// `fetchedJs`; build entries with `adapter:` set to this adapter.
  List<PluginIndexEntry> parse(Object? json, Uri indexUrl);

  /// Converts the downloaded [fetchedJs] of [e] into a Kartka plugin source.
  ///
  /// The index `sha256`, when present, was already verified on [fetchedJs].
  Future<String> buildSource(PluginIndexEntry e, String fetchedJs);
}
