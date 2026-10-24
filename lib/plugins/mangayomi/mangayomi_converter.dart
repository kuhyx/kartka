import 'dart:convert';

import 'package:kartka/plugins/mangayomi/mangayomi_entry.dart';
import 'package:kartka/plugins/mangayomi/shim/adapter_js.dart';
import 'package:kartka/plugins/mangayomi/shim/dom_api_js.dart';
import 'package:kartka/plugins/mangayomi/shim/html_parse_js.dart';
import 'package:kartka/plugins/mangayomi/shim/html_select_js.dart';
import 'package:kartka/plugins/mangayomi/shim/runtime_js.dart';
import 'package:kartka/plugins/runtime/host_api.dart';

/// A Mangayomi extension turned into a Kartka plugin (contracts §6).
class ConvertedPlugin {
  /// Creates a converted plugin.
  const ConvertedPlugin({
    required this.manifest,
    required this.source,
    required this.entry,
  });

  /// Kartka manifest (`id` is `mangayomi-<id>`).
  final PluginManifest manifest;

  /// Plugin JS: shim, source entry, wrapped extension, adapter.
  final String source;

  /// The Mangayomi index entry it came from.
  final MangayomiEntry entry;
}

/// Wraps Mangayomi JS extensions in the Kartka shim.
abstract final class MangayomiConverter {
  /// Builds the Kartka plugin for [entry] from its extension JS [extension].
  ///
  /// The extension runs inside a function scope so its top-level names
  /// (`mangayomiSources`, helpers) cannot collide with the six Kartka entry
  /// points; its `DefaultExtension` class is handed to the adapter. Nothing
  /// is evaluated here and the plugin never `eval`s fetched code.
  ///
  /// Throws [FormatException] when [extension] does not define
  /// `DefaultExtension`.
  static ConvertedPlugin convert(MangayomiEntry entry, String extension) {
    if (!RegExp(r'\bclass\s+DefaultExtension\b').hasMatch(extension)) {
      throw FormatException(
        'Mangayomi extension "${entry.name}" defines no DefaultExtension',
      );
    }
    final source = StringBuffer()
      ..writeln(kShimHtmlParseJs)
      ..writeln(kShimHtmlSelectJs)
      ..writeln(kShimDomApiJs)
      ..writeln(kShimRuntimeJs)
      ..writeln('const __kmSource = ${jsonEncode(entry.raw)};')
      ..writeln('const __kmExtClass = (function () {')
      ..writeln(extension)
      ..writeln('return DefaultExtension;')
      ..writeln('})();')
      ..writeln(kShimAdapterJs);
    return ConvertedPlugin(
      manifest: entry.toManifest(),
      source: source.toString(),
      entry: entry,
    );
  }
}
