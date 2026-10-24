import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/chapter_url_resolver.dart';
import 'package:kartka/tracking/common/progress_rules.dart';
import 'package:kartka/tracking/common/track_binding.dart';
import 'package:kartka/tracking/common/tracker.dart';

/// Receives errors that must not break the progress stream.
typedef TrackingErrorSink = void Function(Object error);

void _ignore(Object _) {}

/// Two-way progress tracking (contracts §9).
///
/// Binds a `MangaKey` to remote ids, listens to [ProgressRepository.watch]
/// for every bound key, pushes local progress up, and on [refresh] pulls
/// remote progress forward. Nothing here lowers a count: pushes go through
/// `Tracker.pushProgress` (never lowers), pulls go through
/// `ProgressRepository.record` (ignored unless ahead), and the binding's
/// `lastPushedChapter` merges by max.
class TrackingService {
  /// Creates the service. `trackers`, `progress` and `resolver` are read
  /// lazily because the registry is complete only after every feature ran.
  new({
    required this._trackers,
    required this._bindings,
    required this._progress,
    ChapterUrlResolver? Function()? resolver,
    DateTime Function()? now,
    TrackingErrorSink? onError,
  }) : _resolver = resolver ?? (() => null),
       _now = now ?? DateTime.now,
       _onError = onError ?? _ignore;

  final List<Tracker> Function() _trackers;
  final BindingStore _bindings;
  final ProgressRepository Function() _progress;
  final ChapterUrlResolver? Function() _resolver;
  final DateTime Function() _now;
  final TrackingErrorSink _onError;

  final Map<MangaKey, StreamSubscription<ReadingProgress?>> _watching = {};
  final Map<String, int> _pending = {};
  final Set<String> _draining = {};
  bool _started = false;

  /// Every registered tracker.
  List<Tracker> get trackers => _trackers();

  /// The tracker with [id], or `null`.
  Tracker? tracker(String id) => trackers.firstWhereOrNull((t) => t.id == id);

  /// Bindings of [key], current list first.
  Stream<List<TrackBinding>> watchBindings(MangaKey key) =>
      _bindings.watch(key);

  /// Starts listening for every stored binding. Idempotent.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (final b in await _bindings.all()) {
      _listen(b.key);
    }
  }

  /// Binds [key] to [remoteId] on [service], pulls, then pushes.
  Future<void> bind(MangaKey key, String service, String remoteId) async {
    await _bindings.put(
      TrackBinding(key: key, service: service, remoteId: remoteId),
    );
    await refresh(key);
    _listen(key);
  }

  /// Drops the [service] binding of [key].
  Future<void> unbind(MangaKey key, String service) async {
    await _bindings.remove(key, service);
    if ((await _of(key)).isEmpty) await _watching.remove(key)?.cancel();
  }

  /// Pulls remote progress of [key] forward into local, where higher.
  Future<void> refresh(MangaKey key) async {
    final bound = await _of(key);
    if (bound.isEmpty) return;
    try {
      final repo = _progress();
      var local = chaptersReadFrom(
        (await repo.watch(key).first)?.chapterNumber,
      );
      for (final b in bound) {
        final t = tracker(b.service);
        if (t == null || !await t.isLoggedIn()) continue;
        final remote = (await t.fetch(b.remoteId))?.chaptersRead ?? 0;
        if (needsPull(local: local, remote: remote) &&
            await _pull(repo, key, remote)) {
          local = remote;
        }
        if (remote > 0) {
          await _bindings.put(b.copyWith(lastPushedChapter: remote));
        }
      }
    } on Object catch (e) {
      _onError(e);
    }
  }

  /// Stops every progress subscription.
  Future<void> dispose() async {
    final subs = [..._watching.values];
    _watching.clear();
    for (final s in subs) {
      await s.cancel();
    }
  }

  Future<bool> _pull(ProgressRepository repo, MangaKey key, int count) async {
    final url = await _resolver()?.chapterUrlFor(key, count);
    if (url == null) return false;
    await repo.record(
      ReadingProgress(
        key: key,
        chapterUrl: url,
        chapterNumber: count.toDouble(),
        page: 0,
        readAt: _now(),
      ),
    );
    await repo.markRead(key, url);
    return true;
  }

  void _listen(MangaKey key) {
    if (_watching.containsKey(key)) return;
    try {
      _watching[key] = _progress()
          .watch(key)
          .listen((p) => unawaited(_onProgress(key, p)), onError: _onError);
    } on Object catch (e) {
      _onError(e);
    }
  }

  Future<void> _onProgress(MangaKey key, ReadingProgress? p) async {
    final local = chaptersReadFrom(p?.chapterNumber);
    if (local == null) return;
    for (final b in await _of(key)) {
      if (alreadyPushed(local: local, lastPushed: b.lastPushedChapter)) {
        continue;
      }
      _enqueue(b, local);
    }
  }

  /// Coalesces pushes per binding: while one is in flight, later targets
  /// collapse into the highest, so paging through chapters costs few calls.
  void _enqueue(TrackBinding b, int local) {
    final slot = '${b.key}\u0000${b.service}';
    _pending[slot] = math.max(_pending[slot] ?? 0, local);
    if (!_draining.add(slot)) return;
    unawaited(_drain(b.key, b.service, slot));
  }

  Future<void> _drain(MangaKey key, String service, String slot) async {
    try {
      while (_pending.containsKey(slot)) {
        await _pushOne(key, service, _pending.remove(slot)!);
      }
    } finally {
      _draining.remove(slot);
    }
  }

  Future<void> _pushOne(MangaKey key, String service, int target) async {
    try {
      final b = (await _of(key)).firstWhereOrNull((x) => x.service == service);
      if (b == null) return;
      if (alreadyPushed(local: target, lastPushed: b.lastPushedChapter)) return;
      final t = tracker(service);
      if (t == null || !await t.isLoggedIn()) return;
      await t.pushProgress(b.remoteId, target);
      await _bindings.put(b.copyWith(lastPushedChapter: target));
    } on Object catch (e) {
      _onError(e);
    }
  }

  Future<List<TrackBinding>> _of(MangaKey key) async =>
      (await _bindings.all()).where((b) => b.key == key).toList();
}
