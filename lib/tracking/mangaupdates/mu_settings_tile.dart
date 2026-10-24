/// More → MangaUpdates: shows who is logged in; logs in or out.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
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
    final out = await confirmDestructive(
      context,
      title: 'Log out of MangaUpdates?',
      message: 'Reading progress stops syncing to MangaUpdates.',
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
        title: const Text('MangaUpdates'),
        subtitle: Text(
          loading
              ? 'Checking…'
              : user == null
              ? 'Not logged in'
              : 'Logged in as $user',
        ),
        enabled: !loading,
        onTap: () => _tap(user),
      );
    },
  );
}
