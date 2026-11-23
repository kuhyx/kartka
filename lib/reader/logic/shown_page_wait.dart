import 'dart:async';

import 'package:kartka/core/source/shown_page_gate.dart';

/// The reader's [ShownPageGate]: holds back background work on sources
/// while a page the reader shows is still loading (28fffd0a). One per app
/// run, shared by every reader route.
class ShownPageWait implements ShownPageGate {
  /// A gate that holds work back at most [maxHold].
  new({this.maxHold = const Duration(seconds: 3)});

  /// The longest [idle] waits: a page stuck on a slow host must not stall
  /// a download behind it.
  final Duration maxHold;

  int _pending = 0;
  Completer<void>? _idle;

  /// Whether a shown page is loading.
  bool get busy => _pending > 0;

  /// The shown page's [bytes] are loading: [idle] waits until they settle.
  void hold(Future<Object?> bytes) {
    _pending++;
    void release() {
      if (--_pending > 0) return;
      _idle?.complete();
      _idle = null;
    }

    bytes
        .then<void>((_) => release(), onError: (Object _) => release())
        .ignore();
  }

  @override
  Future<void> idle() {
    if (_pending == 0) return Future.value();
    return (_idle ??= Completer<void>()).future.timeout(
      maxHold,
      onTimeout: () {},
    );
  }
}
