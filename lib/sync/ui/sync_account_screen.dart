/// More → Sync: status, last sync, "Sync now", sign in / out, and the sync
/// passphrase.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:kartka/sync/ui/passphrase_dialog.dart';
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
  late final StreamSubscription<Map<String, String>> _problemSub;
  late final Future<bool> _hadPassphrase = widget.controller.hasPassphrase();
  bool _hasPassphrase = false;
  Map<String, String> _problems = const {};
  bool _prompted = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
    _sub = widget.controller.changes.listen((s) => setState(() => _status = s));
    unawaited(
      _hadPassphrase.then((has) => _update(() => _hasPassphrase = has)),
    );
    _problemSub = widget.controller.watchProblems().listen(_onProblems);
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    unawaited(_problemSub.cancel());
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (mounted) setState(change);
  }

  Future<void> _onProblems(Map<String, String> problems) async {
    _update(() => _problems = problems);
    // The first secret this device can't open or seal asks, once per visit.
    if (problems.isEmpty || _prompted || await _hadPassphrase) return;
    _prompted = true;
    if (mounted) await _askPassphrase();
  }

  Future<void> _askPassphrase() async {
    final value = await askPassphrase(context, change: _hasPassphrase);
    if (value == null) return;
    await widget.controller.setPassphrase(value);
    _update(() => _hasPassphrase = true);
  }

  @override
  Widget build(BuildContext context) {
    final signedOut = _status.phase == SyncPhase.signedOut;
    final busy = _status.phase == SyncPhase.syncing;
    final error = Theme.of(context).colorScheme.error;
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
          const SizedBox(height: AppSpacing.md),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Sync passphrase'),
            subtitle: Text(
              _hasPassphrase
                  ? 'Set on this device'
                  : 'Not set: the Suwayomi login syncs only under a '
                        'passphrase or a password sign-in',
            ),
            trailing: TextButton(
              onPressed: () => unawaited(_askPassphrase()),
              child: Text(_hasPassphrase ? 'Change' : 'Set'),
            ),
          ),
          for (final problem in _problems.values)
            ListTile(
              leading: Icon(Icons.lock_outline, color: error),
              title: Text(problem, style: TextStyle(color: error)),
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
