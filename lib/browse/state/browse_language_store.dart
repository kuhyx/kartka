import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kartka/browse/language_filter.dart';
import 'package:kartka/platform/key_value_store.dart';

/// The Browse language selection (synced setting `browse.languages`), as a
/// JSON list of [languageBucket] codes in display order.
///
/// Unset means [kDefaultBrowseLanguages]; an empty list means "nothing",
/// not the default. Writers await [ready] so a quick first toggle never
/// overwrites the stored list with one derived from the default.
class BrowseLanguageStore extends ValueNotifier<List<String>> {
  /// Creates the store and starts loading from [_kv]. [reloadOn] carries
  /// synced keys a peer changed; [storageKey] reloads.
  new(this._kv, {Stream<String>? reloadOn}) : super(kDefaultBrowseLanguages) {
    ready = _load();
    reloadOn?.where((k) => k == storageKey).listen((_) => _load());
  }

  /// KeyValueStore key holding the JSON list.
  static const storageKey = 'browse.languages';

  final KeyValueStore _kv;

  /// Completes once the saved selection (if any) is in [value].
  late final Future<void> ready;

  Future<void> _load() async {
    value = _parse(await _kv.get(storageKey)) ?? kDefaultBrowseLanguages;
  }

  static List<String>? _parse(String? raw) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is List && json.every((e) => e is String)) {
        return {for (final e in json.cast<String>()) languageBucket(e)}
            .toList();
      }
    } on FormatException {
      // A corrupt value keeps the default; the next toggle overwrites it.
    }
    return null;
  }

  /// Selects [language] (appended, so it is shown last) or deselects it,
  /// and persists the whole list, including selected languages that no
  /// installed source currently has.
  Future<void> toggle(String language) async {
    await ready;
    final bucket = languageBucket(language);
    final next = value.contains(bucket)
        ? [...value.where((l) => l != bucket)]
        : [...value, bucket];
    value = next;
    await _kv.set(storageKey, jsonEncode(next));
  }
}
