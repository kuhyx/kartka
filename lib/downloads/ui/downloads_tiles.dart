import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kartka/downloads/auto/auto_downloader.dart';
import 'package:kartka/downloads/download_service.dart';
import 'package:kartka/downloads/downloads_snapshot.dart';
import 'package:kartka/downloads/ui/format.dart';

/// More tab: opens the Downloads screen and shows storage used.
class DownloadsNavTile extends StatelessWidget {
  /// Creates the tile.
  const new({required this.service, required this.onOpen, super.key});

  /// Source of the usage figure.
  final DownloadService service;

  /// Navigates to the Downloads screen.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => StreamBuilder<DownloadsSnapshot>(
    stream: service.watchAll(),
    builder: (context, snap) {
      final data = snap.data;
      return ListTile(
        leading: const Icon(Icons.download_outlined),
        title: const Text('Downloads'),
        subtitle: data == null
            ? null
            : Text(
                '${data.queue.length} queued · '
                '${formatBytes(data.index.totalBytes)} used',
              ),
        onTap: onOpen,
      );
    },
  );
}

/// More tab: the "auto-download new chapters" setting.
class AutoDownloadTile extends StatefulWidget {
  /// Creates the tile.
  const new({required this.auto, super.key});

  /// The setting's owner.
  final AutoDownloader auto;

  @override
  State<AutoDownloadTile> createState() => _AutoDownloadTileState();
}

class _AutoDownloadTileState extends State<AutoDownloadTile> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.auto.enabled().then((on) {
        if (mounted) setState(() => _on = on);
      }),
    );
  }

  Future<void> _set({required bool on}) async {
    setState(() => _on = on);
    await widget.auto.setEnabled(enabled: on);
    if (on) unawaited(widget.auto.check()); // record the baseline now
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: const Icon(Icons.downloading_outlined),
    title: const Text('Auto-download new chapters'),
    subtitle: const Text('Library manga, checked while the app is open'),
    value: _on ?? false,
    onChanged: _on == null ? null : (on) => unawaited(_set(on: on)),
  );
}
