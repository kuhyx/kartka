import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/downloads/auto/auto_downloader.dart';
import 'package:kartka/downloads/download_service.dart';
import 'package:kartka/downloads/downloads_snapshot.dart';
import 'package:kartka/downloads/ui/format.dart';

/// More tab: opens the Downloads screen and shows storage used.
class DownloadsNavTile extends StatefulWidget {
  /// Creates the tile.
  const new({required this.service, required this.onOpen, super.key});

  /// Source of the usage figure.
  final DownloadService service;

  /// Navigates to the Downloads screen.
  final VoidCallback onOpen;

  @override
  State<DownloadsNavTile> createState() => _DownloadsNavTileState();
}

class _DownloadsNavTileState extends State<DownloadsNavTile> {
  // Held in state so a rebuild does not resubscribe (and blank the subtitle).
  late final Stream<DownloadsSnapshot> _snapshots = widget.service.watchAll();

  @override
  Widget build(BuildContext context) => StreamBuilder<DownloadsSnapshot>(
    stream: _snapshots,
    builder: (context, snap) {
      final data = snap.data;
      final queued = data?.queue.length;
      final used = data == null ? null : formatBytes(data.index.totalBytes);
      return ListTile(
        leading: const Icon(
          Icons.download_outlined,
          semanticLabel: 'Downloads',
        ),
        title: data == null
            ? null
            : SpokenLabel(
                semanticLabel: '$queued queued · $used used',
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      const Icon(Icons.queue, size: 16),
                      const SizedBox(width: AppSpacing.xs),
                      Text('$queued'),
                      const SizedBox(width: AppSpacing.md),
                      const Icon(Icons.storage, size: 16),
                      const SizedBox(width: AppSpacing.xs),
                      Text(used!),
                    ],
                  ),
                ),
              ),
        onTap: widget.onOpen,
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
    secondary: const Icon(
      Icons.downloading_outlined,
      semanticLabel: 'Auto-download new chapters',
    ),
    value: _on ?? false,
    onChanged: _on == null ? null : (on) => unawaited(_set(on: on)),
  );
}
