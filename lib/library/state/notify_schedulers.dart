import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Runs a coalesced notification (or deferred work) later.
typedef NotifyScheduler = void Function(void Function() run);

/// [NotifyScheduler] for the next event-loop turn.
void nextTurn(void Function() run) => Timer.run(run);

/// [NotifyScheduler] for just before the next frame builds (it schedules
/// one): at most one library rebuild request per frame.
void beforeNextFrame(void Function() run) =>
    SchedulerBinding.instance.scheduleFrameCallback((_) => run());

/// [NotifyScheduler] for the turn after the next frame is drawn, so work
/// that would stall the UI isolate cannot hold that frame back.
void afterNextFrame(void Function() run) => SchedulerBinding.instance
  ..addPostFrameCallback((_) => Timer.run(run))
  ..scheduleFrame();
