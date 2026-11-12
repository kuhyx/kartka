/// More → Sync: status, last sync, "Sync now", sign in / out, the e2e key
/// and the sync passphrase.
library;

import 'dart:async';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show E2ePassphraseButton;
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
    final scheme = Theme.of(context).colorScheme;
    final stamp = syncStamp(_status.lastSync);
    final message = _status.message;
    return Scaffold(
      appBar: AppBar(
        title: const Icon(Icons.cloud_sync_outlined, semanticLabel: 'Sync'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ListTile(
            leading: Icon(
              _icon(_status.phase),
              color: _status.phase == SyncPhase.error ? scheme.error : null,
              semanticLabel: statusLabel(_status),
            ),
            // The server's own error words stay; nothing else is painted.
            title: _status.phase == SyncPhase.error && message != null
                ? Text(message, style: TextStyle(color: scheme.error))
                : null,
            subtitle: Row(
              children: [
                Icon(
                  Icons.history,
                  size: 16,
                  semanticLabel: lastSyncLabel(_status.lastSync),
                ),
                if (stamp != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(stamp),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: signedOut || busy
                ? null
                : () => unawaited(widget.controller.syncNow()),
            child: const Icon(Icons.sync, semanticLabel: 'Sync now'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () =>
                unawaited(widget.controller.manageAccount(context)),
            child: Icon(
              signedOut ? Icons.login : Icons.account_circle_outlined,
              semanticLabel: signedOut ? 'Sign in' : 'Account (sign out)',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ListTile(
            leading: const Icon(
              Icons.key_outlined,
              semanticLabel: 'Sync passphrase',
            ),
            title: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Icon(
                _hasPassphrase ? Icons.lock : Icons.lock_open,
                color: _hasPassphrase ? scheme.primary : scheme.error,
                semanticLabel: _hasPassphrase ? 'Set' : 'Not set',
              ),
            ),
            trailing: IconButton(
              style: IconButton.styleFrom(minimumSize: const Size.square(48)),
              onPressed: () => unawaited(_askPassphrase()),
              icon: Icon(
                _hasPassphrase ? Icons.edit_outlined : Icons.add,
                semanticLabel: _hasPassphrase ? 'Change' : 'Set passphrase',
              ),
            ),
          ),
          if (widget.controller.e2e case final e2e?)
            ListTile(
              leading: const Icon(
                Icons.enhanced_encryption_outlined,
                semanticLabel: 'End-to-end key',
              ),
              trailing: ValueListenableBuilder<bool>(
                valueListenable: e2e.locked,
                builder: (context, locked, _) => E2ePassphraseButton(
                  locked: locked,
                  storage: e2e.storage,
                  onSaved: () => unawaited(widget.controller.unlocked()),
                ),
              ),
            ),
          if (_problems.isNotEmpty)
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final problem in _problems.values)
                  Icon(
                    Icons.lock_outline,
                    color: scheme.error,
                    semanticLabel: problem,
                  ),
              ],
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

/// The status, spoken only (the phase icon paints it).
String statusLabel(SyncStatus s) => switch (s.phase) {
  SyncPhase.signedOut => 'Not signed in',
  SyncPhase.idle => 'Signed in, up to date',
  SyncPhase.syncing => 'Syncing',
  SyncPhase.error => 'Sync failed',
};

/// The last sync in local time, minute precision; null when never.
String? syncStamp(DateTime? at) {
  if (at == null) return null;
  final t = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// "Last sync", spoken only beside the painted [syncStamp].
String lastSyncLabel(DateTime? at) => 'Last sync: ${syncStamp(at) ?? 'never'}';
