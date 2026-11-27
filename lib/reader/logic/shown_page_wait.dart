import 'dart:async';

import 'package:kartka/core/source/shown_page_gate.dart';

/// The reader's [ShownPageGate]: holds back background work on sources
/// while a page the reader shows is still loading (28fffd0a). One per app
/// run, shared by every reader route.
class ShownPageWait implements ShownPageGate {
  /// A gate that holds work back at most [maxHold] after the newest shown
  /// page started, reading [now].
  new({
    this.maxHold = const Duration(seconds: 3),
    this.now = DateTime.now,
    this.onStart,
  });

  /// How long after a shown page started [idle] still waits for it: a page
  /// stuck on a slow host must not stall a download behind it, page after
  /// page.
  final Duration maxHold;

  /// The clock.
  final DateTime Function() now;

  /// Told each time a new shown page starts loading (a rebuild of the same
  /// page is not new): the app cancels background calls then (64f0bd6f).
  final void Function()? onStart;

  final _holds =
      <Object, ({Object owner, Future<Object?> bytes, DateTime at})>{};
  Completer<void>? _idle;

  /// Whether a shown page is loading.
  bool get busy => _holds.isNotEmpty;

  /// The page [owner] shows has [bytes] loading: [idle] waits until they
  /// settle or [releaseAll] drops them.
  /// Holding the same [bytes] again (a rebuild of the same page) keeps its
  /// first start, so [maxHold] still counts from it.
  void hold(Object owner, Future<Object?> bytes) {
    if (_holds.values.any(
      (h) => identical(h.owner, owner) && identical(h.bytes, bytes),
    )) {
      return;
    }
    final token = Object();
    _holds[token] = (owner: owner, bytes: bytes, at: now());
    onStart?.call();
    void release() => _release(token);
    bytes
        .then<void>((_) => release(), onError: (Object _) => release())
        .ignore();
  }

  /// Drops every hold of [owner] (a reader that was left).
  void releaseAll(Object owner) {
    [
      for (final e in _holds.entries)
        if (identical(e.value.owner, owner)) e.key,
    ].forEach(_release);
  }

  void _release(Object token) {
    if (_holds.remove(token) == null || _holds.isNotEmpty) return;
    _idle?.complete();
    _idle = null;
  }

  @override
  Future<void> idle() {
    if (_holds.isEmpty) return Future.value();
    final newest = _holds.values
        .map((h) => h.at)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final left = maxHold - now().difference(newest);
    if (left <= Duration.zero) return Future.value();
    return (_idle ??= Completer<void>()).future.timeout(left, onTimeout: () {});
  }
}
