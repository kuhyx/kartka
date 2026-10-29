import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kartka/library/ports.dart';

/// A [LibraryUpdater] the test drives: counts runs, holds them on [gate].
class FakeUpdater extends ChangeNotifier implements LibraryUpdater {
  @override
  UpdateProgress? progress;

  /// How many times [updateAll] ran.
  int calls = 0;

  /// What every run returns.
  UpdateSummary summary = const UpdateSummary();

  /// When set, runs wait for it.
  Completer<void>? gate;

  @override
  Future<UpdateSummary> updateAll() async {
    calls++;
    await gate?.future;
    return summary;
  }

  /// Publishes [p] as the current progress.
  void show(UpdateProgress? p) {
    progress = p;
    notifyListeners();
  }
}
