/// Reports the diagnostics log's failures to the PC through RTDB
/// (`/kartka/errors/<device>/<id>`), where `tools/errors` collects them.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/diagnostics/report_redact.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_namespaces.dart';
import 'package:kartka/sync/sync_runtime.dart';

/// An [ErrorUploader] over [runtime]'s transport and device id, started:
/// it flushes after each reported append, and [startDelay] after sync
/// first starts (the backlog of an earlier launch). Never starts sync.
ErrorUploader startErrorUploads(
  SyncRuntime runtime, {
  required DiagnosticsLog log,
  required KeyValueStore kv,
  Duration startDelay = const Duration(seconds: 20),
}) {
  final uploader = ErrorUploader(
    log: log,
    kv: kv,
    transport: runtime.transport,
    deviceId: runtime.deviceId,
  )..start();
  unawaited(runtime.started.then((_) => uploader.schedule(startDelay)));
  return uploader;
}

/// Pushes every non-`perf.` entry of [log] to `errors/<device>/<id>`.
///
/// The log is the offline queue: an entry is pending until its id is in
/// the sent set ([sentKey] in [kv]), so a crash, a lost connection or a
/// signed-out device loses nothing, and a retried push is idempotent (the
/// id is a hash of the entry). Writes go straight to the transport, never
/// through the sync engine, so they bump no `revs/` and no peer fetches
/// them. Best-effort: debounced after appends, backing off on failure, and
/// it never throws.
class ErrorUploader {
  /// An uploader of [log] over [transport] as device [deviceId].
  new({
    required this.log,
    required this.kv,
    required this.transport,
    required this.deviceId,
  });

  /// RTDB namespace under `/kartka`.
  static const root = 'errors';

  /// Where the ids already pushed are kept.
  static const sentKey = 'errors.sent';

  /// Most ids remembered (above the log's own 2000-entry cap).
  static const maxSent = 2500;

  /// Entries per RTDB write.
  static const batch = 50;

  /// Entries per flush; the rest wait for the next one.
  static const maxPerFlush = 200;

  /// Quiet time after an append before a flush.
  static const debounce = Duration(seconds: 5);

  /// First retry delay after a failed push; doubles up to [maxBackoff].
  static const minBackoff = Duration(seconds: 30);

  /// Longest retry delay.
  static const maxBackoff = Duration(minutes: 15);

  /// The diagnostics log (shared, `DiagnosticsLog.of`).
  final DiagnosticsLog log;

  /// Holds the sent set.
  final KeyValueStore kv;

  /// The sync transport; null while signed out.
  final TransportOpener transport;

  /// This install's device id.
  final Future<String> Function() deviceId;

  StreamSubscription<DiagnosticEntry>? _sub;
  Timer? _timer;
  Duration _backoff = minBackoff;
  Future<bool> _tail = Future.value(true);

  /// The RTDB key of [entry]: a hash of its JSON, so a re-push is a no-op.
  static String idOf(DiagnosticEntry entry) => sha1
      .convert(utf8.encode(jsonEncode(entry.toJson())))
      .toString()
      .substring(0, 20);

  static bool _reported(DiagnosticEntry e) => !e.kind.startsWith('perf.');

  /// Starts flushing [debounce] after each reported append.
  void start() => _sub ??= log.appended.listen((e) {
    if (_reported(e)) schedule();
  });

  /// Flushes after [delay] (default [debounce]), replacing a pending one.
  void schedule([Duration delay = debounce]) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush()));
  }

  /// Stops listening and cancels a pending flush.
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    _timer?.cancel();
  }

  /// Pushes what is pending; true when nothing is left. Flushes run one at
  /// a time; a failed push schedules a retry with backoff.
  Future<bool> flush() => _tail = _tail.then((_) => _flushOnce());

  Future<bool> _flushOnce() async {
    try {
      final sent = await _loadSent();
      final pending = [
        for (final e in await log.entries())
          if (_reported(e) && !sent.contains(idOf(e))) e,
      ];
      if (pending.isEmpty) return true;
      final t = await transport();
      if (t == null) return false;
      final device = rtdbKey(await deviceId());
      final now = pending.take(maxPerFlush).toList();
      for (var i = 0; i < now.length; i += batch) {
        final chunk = now.sublist(i, math.min(i + batch, now.length));
        await t.patch({
          for (final e in chunk) '$root/$device/${idOf(e)}': _payload(e),
        });
        sent.addAll(chunk.map(idOf));
        await _saveSent(sent);
      }
      _backoff = minBackoff;
      return pending.length <= maxPerFlush;
    } on Object {
      schedule(_backoff);
      _backoff = _backoff * 2 > maxBackoff ? maxBackoff : _backoff * 2;
      return false;
    }
  }

  /// The entry's JSON with every string through [redactForReport].
  static Map<String, Object?> _payload(DiagnosticEntry e) => {
    for (final MapEntry(:key, :value) in e.toJson().entries)
      key: switch (value) {
        final String s => redactForReport(s),
        final List<Object?> l => [for (final f in l) redactForReport('$f')],
        _ => value,
      },
  };

  Future<List<String>> _loadSent() async {
    try {
      final raw = jsonDecode(await kv.get(sentKey) ?? '[]') as List<Object?>;
      return raw.cast<String>().toList();
    } on Object {
      return [];
    }
  }

  Future<void> _saveSent(List<String> sent) async {
    final kept = sent.length > maxSent
        ? sent.sublist(sent.length - maxSent)
        : sent;
    await kv.set(sentKey, jsonEncode(kept));
  }
}
