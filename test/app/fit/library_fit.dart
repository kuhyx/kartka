import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/library/ui/library_cell.dart';
import 'package:kartka/library/ui/library_screen.dart';

import '../../library/support/fakes.dart';
import 'fit_harness.dart';

/// Library with [count] manga: more than one screen of covers.
Future<FitScreen> libraryFit({int count = 60}) async {
  final f = Fakes();
  for (var i = 0; i < count; i++) {
    await f.deps.repos.library.upsert(
      entry('/manga/$i', title: 'Manga number $i', addedDays: i),
    );
  }
  return FitScreen(
    tab: KartkaTab.library,
    screen: (_) => LibraryScreen(deps: f.deps),
    tiles: find.byType(LibraryCell),
  );
}
