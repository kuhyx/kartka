/// More → Sync: status, last sync, "Sync now", and sign in / out.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:kartka/sync/ui/sync_account_controller.dart';

/// The sync account screen.
class SyncAccountScreen extends StatefulWidget {
  /// Shows and drives [controller].
  const new({required this.controller, super.key});

  /// What the screen drives.
  final SyncAccountController controller;

  @override
  State<SyncAccountScreen> createState() => _SyncAccountScreenState();
}

class _SyncAccountScreenState extends State<SyncAccountScreen> {
  late SyncStatus _status = widget.controller.status;
  late final StreamSubscription<SyncStatus> _sub;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
    _sub = widget.controller.changes.listen((s) => setState(() => _status = s));
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signedOut = _status.phase == SyncPhase.signedOut;
    final busy = _status.phase == SyncPhase.syncing;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ListTile(
            leading: Icon(_icon(_status.phase)),
            title: Text(statusLabel(_status)),
            subtitle: Text(lastSyncLabel(_status.lastSync)),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: signedOut || busy
                ? null
                : () => unawaited(widget.controller.syncNow()),
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () =>
                unawaited(widget.controller.manageAccount(context)),
            icon: const Icon(Icons.account_circle_outlined),
            label: Text(signedOut ? 'Sign in' : 'Account (sign out)'),
          ),
        ],
      ),
    );
  }

  static IconData _icon(SyncPhase phase) => switch (phase) {
    SyncPhase.signedOut => Icons.cloud_off_outlined,
    SyncPhase.idle => Icons.cloud_done_outlined,
    SyncPhase.syncing => Icons.cloud_sync_outlined,
    SyncPhase.error => Icons.error_outline,
  };
}

/// One-line status text.
String statusLabel(SyncStatus s) => switch (s.phase) {
  SyncPhase.signedOut => 'Not signed in: this device only keeps local data',
  SyncPhase.idle => 'Signed in, up to date',
  SyncPhase.syncing => 'Syncing…',
  SyncPhase.error => 'Sync failed: ${s.message ?? 'unknown error'}',
};

/// "Last sync" text in local time, minute precision.
String lastSyncLabel(DateTime? at) {
  if (at == null) return 'Last sync: never';
  final t = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Last sync: ${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
