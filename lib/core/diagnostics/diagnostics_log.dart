import 'dart:async';
import 'dart:convert';

import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/platform/blob_store.dart';

/// The app's rolling diagnostics log: one JSON line per [DiagnosticEntry].
///
/// Lives in the platform's `diagnostics` store (`KartkaPlatform.diagnostics`)
/// where a PC can fetch it: on Android the app-specific external files dir
/// (`adb pull`, no root), on the web build the wrapper's `/files` root. The
/// oldest lines roll off past [maxEntries] or [maxBytes].
///
/// A [BlobStore] has no append, so each write rewrites the file. Use `.of` so
/// every part shares one instance per store and the writes stay serialised.
class DiagnosticsLog {
  /// A log in [_store] under [key].
  new(
    this._store, {
    this.key = defaultKey,
    this.maxBytes = 1024 * 1024,
    this.maxEntries = 2000,
  });

  /// The shared log on [store].
  factory of(BlobStore store) => _shared[store] ??= DiagnosticsLog(store);

  static final _shared = Expando<DiagnosticsLog>('diagnostics');

  /// Where the log file lives in its store.
  static const defaultKey = 'diagnostics/kartka-diagnostics.jsonl';

  final BlobStore _store;

  /// Blob key of the log file.
  final String key;

  /// Largest file size kept, in bytes.
  final int maxBytes;

  /// Most entries kept.
  final int maxEntries;

  /// The screen on top (a go_router pattern), stamped onto every appended
  /// entry that names none. Set by the app's screen observer.
  String? route;

  final _appended = StreamController<DiagnosticEntry>.broadcast();

  /// Each entry once it is written to the store (so a reader sees it).
  Stream<DiagnosticEntry> get appended => _appended.stream;

  List<String>? _lines;
  int _bytes = 0;
  Future<void> _tail = Future.value();

  /// Adds [entry]. Never throws: diagnostics must not break what failed.
  Future<void> append(DiagnosticEntry entry) {
    final here = route;
    final stamped = entry.route == null && here != null
        ? entry.withRoute(here)
        : entry;
    return _tail = _tail.then((_) => _append(stamped));
  }

  Future<void> _append(DiagnosticEntry entry) async {
    try {
      final lines = await _load();
      final line = jsonEncode(entry.toJson());
      lines.add(line);
      _bytes += _size(line);
      while (lines.length > 1 &&
          (lines.length > maxEntries || _bytes > maxBytes)) {
        _bytes -= _size(lines.removeAt(0));
      }
      await _store.put(key, utf8.encode(lines.map((l) => '$l\n').join()));
      _appended.add(entry);
    } on Object {
      // Unreadable store: drop this entry rather than clobber the file. A
      // failed write keeps the entry in memory for the next append.
    }
  }

  static int _size(String line) => utf8.encode(line).length + 1;

  Future<List<String>> _load() async {
    final cached = _lines;
    if (cached != null) return cached;
    final bytes = await _store.get(key);
    final lines = [
      for (final l in const LineSplitter().convert(utf8.decode(bytes ?? [])))
        if (l.trim().isNotEmpty) l,
    ];
    _bytes = lines.fold(0, (sum, l) => sum + _size(l));
    return _lines = lines;
  }

  /// Every readable entry, oldest first.
  Future<List<DiagnosticEntry>> entries() async {
    await _tail;
    try {
      return [for (final line in await _load()) ?_decode(line)];
    } on Object {
      return const [];
    }
  }

  static DiagnosticEntry? _decode(String line) {
    try {
      return DiagnosticEntry.fromJson(jsonDecode(line) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }
}
