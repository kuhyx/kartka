/// More → MangaUpdates: shows who is logged in; logs in or out.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/confirm_mark.dart';
import 'package:kartka/tracking/mangaupdates/mu_login_sheet.dart';
import 'package:kartka/tracking/mangaupdates/mu_tracker.dart';

/// Settings tile for the MangaUpdates tracker.
class MuSettingsTile extends StatefulWidget {
  /// Creates the tile for [tracker].
  const new({required this.tracker, super.key});

  /// The tracker to log in or out.
  final MangaUpdatesTracker tracker;

  @override
  State<MuSettingsTile> createState() => _MuSettingsTileState();
}

class _MuSettingsTileState extends State<MuSettingsTile> {
  late Future<String?> _user = widget.tracker.username();

  void _reload() {
    if (!mounted) return;
    setState(() {
      _user = widget.tracker.username();
    });
  }

  Future<void> _tap(String? user) async {
    if (user == null) {
      await showMuLoginSheet(context, widget.tracker.loginWith);
      _reload();
      return;
    }
    final out = await confirmMark(
      context,
      icon: Icons.logout,
      semanticLabel: 'Log out of MangaUpdates?',
      confirmIcon: Icons.logout,
      confirmLabel: 'Log out',
    );
    if (!out) return;
    await widget.tracker.logout();
    _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _user,
    builder: (context, snap) {
      final user = snap.data;
      final loading = snap.connectionState != ConnectionState.done;
      return ListTile(
        leading: const Icon(Icons.sync_alt),
        // The tracker's own name, like a source name: content, not chrome.
        title: Text(widget.tracker.name),
        subtitle: loading
            ? const LinearProgressIndicator()
            : Row(
                children: [
                  Icon(
                    user == null ? Icons.person_off_outlined : Icons.person,
                    size: 16,
                    semanticLabel: user == null ? 'Not logged in' : 'Logged in',
                  ),
                  if (user != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Text(user),
                  ],
                ],
              ),
        enabled: !loading,
        onTap: () => _tap(user),
      );
    },
  );
}
