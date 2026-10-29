/// The real [RtdbReader]: reads through the sync transport and polls for
/// [RtdbReader.watch]. Signed out reads as "nothing there" (null).
library;

import 'dart:async';

import 'package:kartka/sync/json_equal.dart';
import 'package:kartka/sync/rtdb_reader.dart';
import 'package:kartka/sync/rtdb_transport.dart';

/// Opens the transport, or null while signed out.
typedef ReaderOpener = Future<RtdbTransport?> Function();

/// [RtdbReader] over an [RtdbTransport].
class PollingRtdbReader implements RtdbReader {
  /// Reads via [open]; [watch] re-reads every [interval] while listened to.
  new(this.open, {this.interval = const Duration(minutes: 1)});

  /// Transport factory.
  final ReaderOpener open;

  /// Poll period for [watch]. Source health changes weekly, so a minute is
  /// generous; nothing polls while no one listens. An unchanged tree is
  /// detected by [jsonEquals] (no re-encode) and not re-emitted.
  final Duration interval;

  @override
  Future<Object?> get(String path) async {
    final transport = await open();
    if (transport == null) return null;
    return await transport.get(path);
  }

  @override
  Stream<Object?> watch(String path) {
    Timer? timer;
    // `(value,)` once something was emitted; a record, so null data is
    // distinguishable from "nothing yet".
    (Object?,)? last;
    late final StreamController<Object?> controller;
    Future<void> tick() async {
      try {
        final value = await get(path);
        final seen = last;
        if (controller.isClosed) return;
        if (seen != null && jsonEquals(seen.$1, value)) return;
        last = (value,);
        controller.add(value);
      } on Exception catch (e, s) {
        // Surface the failure, keep polling: the next tick may succeed.
        // Forget the last value so that success re-emits even when the
        // data is unchanged; otherwise the error would stick on screen.
        last = null;
        if (!controller.isClosed) controller.addError(e, s);
      }
    }

    controller = StreamController<Object?>(
      onListen: () {
        unawaited(tick());
        timer = Timer.periodic(interval, (_) => unawaited(tick()));
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }
}
