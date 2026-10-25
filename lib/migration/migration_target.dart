import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';

/// Atsumaru's id through Suwayomi (Keiyoushi `en.atsumaru`, contracts §1).
const String atsumaruSourceId = 'suwayomi:2327480808438768017';

/// Atsumaru's display name, matched when it arrives under another id (a
/// plugin or a native port).
const String atsumaruName = 'Atsumaru';

/// Whether [ref] is Atsumaru.
bool isAtsumaru(SourceRef ref) =>
    ref.id == atsumaruSourceId ||
    ref.name.toLowerCase() == atsumaruName.toLowerCase();

String _normal(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Whether two titles are the same up to case and whitespace: an exact
/// match the review screen pre-ticks.
bool isExactTitle(String a, String b) => _normal(a) == _normal(b);

/// The Atsumaru source among [providers], waiting up to [timeout] for it:
/// a provider may emit `[]` first and its real list later (contracts §15).
/// Null when none shows up in time.
Future<MangaSource?> findTarget(
  List<SourceProvider> providers, {
  Duration timeout = const Duration(seconds: 10),
}) {
  final found = Completer<MangaSource?>();
  final subs = <StreamSubscription<List<MangaSource>>>[];
  void finish(MangaSource? source) {
    if (found.isCompleted) return;
    found.complete(source);
    for (final s in subs) {
      unawaited(s.cancel());
    }
  }

  final timer = Timer(timeout, () => finish(null));
  for (final p in providers) {
    subs.add(
      p.watch().listen((sources) {
        for (final s in sources) {
          if (isAtsumaru(s.ref)) return finish(s);
        }
      }),
    );
  }
  return found.future.whenComplete(timer.cancel);
}
