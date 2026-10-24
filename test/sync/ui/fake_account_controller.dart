import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:kartka/sync/ui/sync_account_controller.dart';

/// A [SyncAccountController] that records what the screen asks of it.
class FakeAccountController implements SyncAccountController {
  new(this.status, {this.passphrase = false, this.problemsNow = const {}});

  @override
  SyncStatus status;

  /// Whether this device has a passphrase.
  bool passphrase;

  /// What [watchProblems] emits first.
  Map<String, String> problemsNow;

  final _changes = StreamController<SyncStatus>.broadcast();
  final _problems = StreamController<Map<String, String>>.broadcast();
  int syncs = 0;
  int manages = 0;
  int refreshes = 0;
  final passphrases = <String>[];

  void emit(SyncStatus s) => _changes.add(status = s);

  void emitProblems(Map<String, String> p) => _problems.add(problemsNow = p);

  @override
  Stream<SyncStatus> get changes => _changes.stream;

  @override
  Future<void> syncNow() async => syncs++;

  @override
  Future<void> refresh() async => refreshes++;

  @override
  Future<void> manageAccount(BuildContext context) async => manages++;

  @override
  Stream<Map<String, String>> watchProblems() async* {
    yield problemsNow;
    yield* _problems.stream;
  }

  @override
  Future<bool> hasPassphrase() async => passphrase;

  @override
  Future<void> setPassphrase(String value) async {
    passphrases.add(value);
    passphrase = true;
  }
}
