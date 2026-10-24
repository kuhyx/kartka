import 'package:kartka/backup_import/tracker_binding_sink.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';

/// In-memory repositories that count writes, for idempotency assertions.
class FakeLibrary implements LibraryRepository {
  final Map<MangaKey, LibraryEntry> entries = {};
  int writes = 0;
  bool failOnWrite = false;
  Future<void>? gate;

  @override
  Stream<List<LibraryEntry>> watch() =>
      Stream.value(entries.values.where((e) => !e.removed).toList());

  @override
  Future<void> upsert(LibraryEntry e) async {
    await gate;
    if (failOnWrite) throw StateError('disk full');
    writes++;
    entries[e.key] = e;
  }

  @override
  Future<void> remove(MangaKey key) async {}
}

class FakeCategories implements CategoryRepository {
  final Map<String, Category> categories = {};
  final Map<MangaKey, Set<String>> membership = {};
  int writes = 0;

  @override
  Stream<List<Category>> watch() => Stream.value(categories.values.toList());

  @override
  Future<void> upsert(Category c) async {
    writes++;
    categories[c.id] = c;
  }

  @override
  Future<void> setMembership(
    MangaKey key,
    String categoryId,
    bool member,
  ) async {
    writes++;
    final set = membership.putIfAbsent(key, () => {});
    member ? set.add(categoryId) : set.remove(categoryId);
  }

  @override
  Stream<Map<MangaKey, Set<String>>> watchMembership() => Stream.value({
    for (final e in membership.entries) e.key: {...e.value},
  });
}

class FakeProgress implements ProgressRepository {
  final Map<MangaKey, ReadingProgress> progress = {};
  final Map<MangaKey, Set<String>> read = {};
  final Map<MangaKey, Set<String>> unread = {};
  int writes = 0;

  @override
  Stream<ReadingProgress?> watch(MangaKey key) => Stream.value(progress[key]);

  @override
  Future<void> record(ReadingProgress p) async {
    writes++;
    progress[p.key] = p;
  }

  @override
  Future<void> markRead(MangaKey key, String chapterUrl) async {
    writes++;
    read.putIfAbsent(key, () => {}).add(chapterUrl);
  }

  @override
  Future<void> markUnread(MangaKey key, String chapterUrl) async {
    read[key]?.remove(chapterUrl);
    unread.putIfAbsent(key, () => {}).add(chapterUrl);
  }

  @override
  Stream<Map<String, bool>> readMarks(MangaKey key) => Stream.value({
    for (final u in unread[key] ?? <String>{}) u: false,
    for (final u in read[key] ?? <String>{}) u: true,
  });

  @override
  Stream<Set<String>> readChapters(MangaKey key) =>
      Stream.value({...?read[key]});
}

class FakeBindings implements TrackerBindingSink {
  final Map<String, (String, int)> bound = {};
  int writes = 0;

  @override
  Future<bool> bind(
    MangaKey key,
    String service,
    String remoteId, {
    int lastPushedChapter = 0,
  }) async {
    final k = '$key#$service';
    if (bound[k] == (remoteId, lastPushedChapter)) return false;
    writes++;
    bound[k] = (remoteId, lastPushedChapter);
    return true;
  }
}
