import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/library/state/entry_facts.dart';
import 'package:kartka/library/state/library_deps.dart';
import 'package:kartka/library/state/library_item.dart';
import 'package:kartka/library/state/library_query.dart';

/// Entries removed together, kept for undo.
typedef RemovedBatch = ({List<LibraryEntry> entries, DateTime at});

/// State of the Library tab: the joined items, category tabs, the query and
/// the multi-selection. Every write goes through the decorated repositories.
class LibraryController extends ChangeNotifier {
  /// Creates the controller; call [start] to subscribe.
  new(this.deps) {
    _facts = FactsTracker(deps, notifyListeners);
  }

  /// Repositories, ports and clock.
  final LibraryDeps deps;
  late final FactsTracker _facts;
  final _subs = <StreamSubscription<Object?>>[];

  Map<MangaKey, LibraryEntry> _entries = {};
  Map<MangaKey, Set<String>> _membership = {};
  List<Category> _categories = const [];
  LibraryQuery _query = const LibraryQuery();
  final Set<MangaKey> _selected = {};
  bool _selecting = false;
  bool _loaded = false;

  /// Whether the library has been read once.
  bool get loaded => _loaded;

  /// Live categories by order: the tabs after "All".
  List<Category> get categories => _categories;

  /// Current tab, filters, search and sort.
  LibraryQuery get query => _query;
  set query(LibraryQuery q) {
    _query = q;
    notifyListeners();
  }

  /// Every entry joined with its facts, unsorted.
  List<LibraryItem> get items => [for (final e in _entries.values) _item(e)];

  /// [items] after [query].
  List<LibraryItem> get visible => applyQuery(items, _query);

  /// Whether multi-select mode is on.
  bool get selecting => _selecting;

  /// Selected keys.
  Set<MangaKey> get selected => Set.unmodifiable(_selected);

  /// Subscribes to the repositories.
  void start() {
    final repos = deps.repos;
    _subs
      ..add(repos.library.watch().listen(_onEntries))
      ..add(repos.categories.watch().listen(_onCategories))
      ..add(
        repos.categories.watchMembership().listen((m) {
          _membership = m;
          notifyListeners();
        }),
      );
  }

  void _onEntries(List<LibraryEntry> entries) {
    _entries = {for (final e in entries) e.key: e};
    _selected.retainAll(_entries.keys);
    _facts.track(_entries.keys.toSet());
    _loaded = true;
    notifyListeners();
  }

  void _onCategories(List<Category> categories) {
    _categories = categories;
    final tab = _query.categoryId;
    if (tab != null && !categories.any((c) => c.id == tab)) {
      _query = _query.copyWith(clearCategory: true);
    }
    notifyListeners();
  }

  LibraryItem _item(LibraryEntry e) {
    final f = _facts.of(e.key);
    return LibraryItem(
      key: e.key,
      sourceId: e.sourceId,
      mangaUrl: e.mangaUrl,
      title: e.title,
      coverUrl: e.coverUrl,
      addedAt: e.addedAt,
      lastReadAt: f.lastReadAt,
      unread: f.unread,
      downloaded: f.downloaded,
      tracked: f.tracked,
      categoryIds: _membership[e.key] ?? const {},
    );
  }

  /// Enters multi-select with nothing selected (keyboard path).
  void startSelecting() {
    _selecting = true;
    notifyListeners();
  }

  /// Toggles [key] and enters multi-select.
  void toggle(MangaKey key) {
    _selecting = true;
    if (!_selected.remove(key)) _selected.add(key);
    notifyListeners();
  }

  /// Selects every visible entry.
  void selectAllVisible() {
    _selecting = true;
    _selected.addAll(visible.map((i) => i.key));
    notifyListeners();
  }

  /// Leaves multi-select.
  void clearSelection() {
    _selecting = false;
    _selected.clear();
    notifyListeners();
  }

  /// Removes the selection from the library; pass the result to [restore].
  Future<RemovedBatch> removeSelected() async {
    final at = deps.clock();
    final entries = [for (final k in _selected) _entries[k]!];
    clearSelection();
    for (final e in entries) {
      await deps.repos.library.remove(e.key);
    }
    return (entries: entries, at: at);
  }

  /// Undoes [removeSelected], stamped past the tombstones it wrote.
  Future<void> restore(RemovedBatch batch) async {
    for (final e in batch.entries) {
      final tombstone = nextStamp(batch.at, e.updatedAt);
      await deps.repos.library.upsert(
        e.copyWith(
          removed: false,
          updatedAt: nextStamp(deps.clock(), tombstone),
        ),
      );
    }
  }

  /// Per category: `true` if every selected entry is in it, `false` if
  /// none is, `null` if some are.
  Map<String, bool?> selectionMembership() => {
    for (final c in _categories) c.id: _allOrNone(c.id),
  };

  bool? _allOrNone(String id) {
    final hits = _selected.where((k) => _membership[k]?.contains(id) ?? false);
    if (hits.isEmpty) return false;
    return hits.length == _selected.length ? true : null;
  }

  /// Applies [changes] (category id to member) to every selected entry.
  Future<void> setCategories(Map<String, bool> changes) async {
    for (final key in _selected.toList()) {
      for (final MapEntry(key: id, value: member) in changes.entries) {
        await deps.repos.categories.setMembership(key, id, member);
      }
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_facts.dispose());
    super.dispose();
  }
}
