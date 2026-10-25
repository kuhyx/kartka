import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/reader/logic/chapter_strip.dart';
import 'package:kartka/reader/logic/reader_keys.dart';
import 'package:kartka/reader/logic/tap_zones.dart';
import 'package:kartka/reader/platform/reader_system.dart';
import 'package:kartka/reader/state/reader_deps.dart';
import 'package:kartka/reader/state/reader_session.dart';
import 'package:kartka/reader/ui/chapter_transition.dart';
import 'package:kartka/reader/ui/paged_reader_view.dart';
import 'package:kartka/reader/ui/reader_controls.dart';
import 'package:kartka/reader/ui/reader_page_image.dart';
import 'package:kartka/reader/ui/reader_settings_panel.dart';
import 'package:kartka/reader/ui/reader_view_controller.dart';
import 'package:kartka/reader/ui/webtoon_reader_view.dart';

part 'reader_screen_body.dart';

/// The reader for one chapter (route `/read/:sourceId/:mangaUrl/:chapterUrl`).
class ReaderScreen extends StatefulWidget {
  /// Reads [chapterUrl] of [mangaUrl] from [sourceId].
  const new({
    required this.sourceId,
    required this.mangaUrl,
    required this.chapterUrl,
    required this.deps,
    required this.system,
    required this.onOpenChapter,
    required this.onExit,
    super.key,
  });

  /// Source id from the route.
  final String sourceId;

  /// Manga URL from the route.
  final String mangaUrl;

  /// Chapter URL from the route.
  final String chapterUrl;

  /// Repositories, source lookup and image loading.
  final ReaderDeps deps;

  /// Wake lock and fullscreen.
  final ReaderSystem system;

  /// Replaces this reader with the given chapter of the same manga.
  final ValueChanged<ChapterInfo> onOpenChapter;

  /// Leaves the reader.
  final VoidCallback onExit;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _view = ReaderViewController();
  late ReaderSession _session;
  bool _menu = false;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _session = _open();
    unawaited(widget.system.keepAwake(on: true));
  }

  ReaderSession _open() {
    final s = ReaderSession(
      sourceId: widget.sourceId,
      mangaUrl: widget.mangaUrl,
      chapterUrl: widget.chapterUrl,
      deps: widget.deps,
    )..addListener(_changed);
    unawaited(s.open());
    return s;
  }

  void _changed() => setState(() {});

  void _retryOpen() {
    _session.dispose();
    setState(() => _session = _open());
  }

  @override
  void dispose() {
    _session.dispose();
    unawaited(widget.system.keepAwake(on: false));
    if (_fullscreen) unawaited(widget.system.setFullscreen(on: false));
    super.dispose();
  }

  void _toggleFullscreen() {
    // Prefer the platform's answer: the browser leaves fullscreen on its own
    // Esc, which would otherwise leave this flag stale.
    _fullscreen = !(widget.system.isFullscreen ?? _fullscreen);
    unawaited(widget.system.setFullscreen(on: _fullscreen));
  }

  void _openChapter(ChapterInfo? chapter) {
    if (chapter != null) widget.onOpenChapter(chapter);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final intent = intentForKey(
      event.logicalKey,
      mode: _session.mode,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );
    switch (intent) {
      case null:
        return KeyEventResult.ignored;
      case ReaderIntent.next:
        _view.step(1);
      case ReaderIntent.previous:
        _view.step(-1);
      case ReaderIntent.toggleFullscreen:
        if (event is KeyDownEvent) _toggleFullscreen();
      case ReaderIntent.back:
        if (event is KeyDownEvent) widget.onExit();
    }
    return KeyEventResult.handled;
  }

  void _onTap(Offset position, Size size) {
    final s = _session;
    switch (resolveTap(
      layout: s.settings.tapLayout,
      position: position,
      size: size,
      mode: s.mode,
      invert: s.settings.invertTaps,
    )) {
      case TapAction.next:
        _view.step(1);
      case TapAction.previous:
        _view.step(-1);
      case TapAction.menu:
        setState(() => _menu = !_menu);
    }
  }

  Future<void> _showSettings() => showModalBottomSheet<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: _session,
      builder: (context, _) => ReaderSettingsPanel(
        settings: _session.settings,
        onChanged: _session.updateSettings,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: switch (_session.phase) {
        ReaderPhase.loading => const Center(child: CircularProgressIndicator()),
        ReaderPhase.failed => _failed(context),
        ReaderPhase.ready => Stack(
          children: [
            Positioned.fill(child: _reader()),
            if (_menu) Positioned.fill(child: _controls()),
          ],
        ),
      },
    ),
  );
}
