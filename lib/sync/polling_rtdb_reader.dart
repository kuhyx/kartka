/// The real [RtdbReader]: reads through the sync transport and polls for
/// [RtdbReader.watch]. Signed out reads as "nothing there" (null).
library;

import 'dart:async';

import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_reader.dart';
import 'package:kartka/sync/rtdb_transport.dart';

/// Opens the transport, or null while signed out.
typedef ReaderOpener = Future<RtdbTransport?> Function();

/// [RtdbReader] over an [RtdbTransport].
class PollingRtdbReader implements RtdbReader {
  /// Reads via [open]; [watch] re-reads every [interval] while listened to.
  PollingRtdbReader(
    this.open, {
    this.interval = const Duration(minutes: 1),
  });

  /// Transport factory.
  final ReaderOpener open;

  /// Poll period for [watch]. Source health changes weekly, so a minute is
  /// generous; nothing polls while no one listens.
  final Duration interval;

  @override
  Future<Object?> get(String path) async {
    final transport = await open();
    return transport?.get(path);
  }

  @override
  Stream<Object?> watch(String path) {
    Timer? timer;
    String? last;
    late final StreamController<Object?> controller;
    Future<void> tick() async {
      try {
        final value = await get(path);
        final text = canon(value);
        if (text == last || controller.isClosed) return;
        last = text;
        controller.add(value);
      } on Exception catch (e, s) {
        // Surface the failure, keep polling: the next tick may succeed.
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
