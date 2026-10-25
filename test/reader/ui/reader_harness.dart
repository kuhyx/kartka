import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/state/reader_deps.dart';
import 'package:kartka/reader/ui/reader_screen.dart';

import '../support/fakes.dart';

/// Chapters 1-3, listed newest first like most sources.
const harnessChapters = [
  ChapterInfo(url: '/c/3', name: 'Ch. 3', number: 3),
  ChapterInfo(url: '/c/2', name: 'Ch. 2', number: 2),
  ChapterInfo(url: '/c/1', name: 'Ch. 1', number: 1),
];

/// A reader on chapter 2 (4 pages) with every collaborator faked.
class ReaderHarness {
  new({FakeSource? source}) {
    this.source =
        source ??
        FakeSource(
          chapterList: harnessChapters,
          pageMap: {'/c/2': fakePages('/c/2', 4)},
        );
  }

  late final FakeSource source;
  final kv = MemoryKeyValueStore();
  final progress = FakeProgress();
  final system = FakeReaderSystem();
  final opened = <String>[];
  final openedAtEnd = <String>[];
  final diagnostics = DiagnosticsLog(MemoryBlobStore());
  final loaded = <String>[];
  int exits = 0;

  ReaderPrefs get prefs => ReaderPrefs(kv);

  /// Pumps the screen and lets it load.
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          sourceId: source.id,
          mangaUrl: '/m/1',
          chapterUrl: '/c/2',
          system: system,
          onOpenChapter: (c, {atEnd = false}) {
            opened.add(c.url);
            if (atEnd) openedAtEnd.add(c.url);
          },
          onExit: () => exits++,
          deps: ReaderDeps(
            findSource: (id) async => id == source.id ? source : null,
            progress: progress,
            prefs: prefs,
            diagnostics: diagnostics,
            loadImage: (p) async {
              loaded.add(p.imageUrl);
              return onePixelPng;
            },
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Pumps past animations and the double-tap window without waiting on
  /// timers that never settle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
