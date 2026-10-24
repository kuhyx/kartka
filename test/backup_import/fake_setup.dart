import 'package:kartka/backup_import/backup_importer.dart';

import 'fakes.dart';

/// A wired-up importer over in-memory fakes.
class Fakes {
  new({bool withBindings = true}) {
    importer = BackupImporter(
      library: library,
      categories: categories,
      progress: progress,
      bindings: withBindings ? bindings : null,
    );
  }

  final FakeLibrary library = FakeLibrary();
  final FakeCategories categories = FakeCategories();
  final FakeProgress progress = FakeProgress();
  final FakeBindings bindings = FakeBindings();
  late final BackupImporter importer;

  int get totalWrites =>
      library.writes + categories.writes + progress.writes + bindings.writes;
}
