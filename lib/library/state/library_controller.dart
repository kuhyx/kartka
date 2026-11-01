import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/scheduler.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/library/state/entry_facts.dart';
import 'package:kartka/library/state/library_deps.dart';
import 'package:kartka/library/state/library_item.dart';
import 'package:kartka/library/state/library_query.dart';
import 'package:kartka/library/state/source_availability.dart';

/// Runs a coalesced notification later.
typedef NotifyScheduler = void Function(void Function() run);

/// [NotifyScheduler] for the next event-loop turn.
void nextTurn(void Function() run) => Timer.run(run);

/// [NotifyScheduler] for just before the next frame builds (it schedules
/// one): at most one library rebuild request per frame.
void beforeNextFrame(void Function() run) =>
    SchedulerBinding.instance.scheduleFrameCallback((_) => run());

/// Entries removed together, kept for undo.
typedef RemovedBatch = ({List<LibraryEntry> entries, DateTime at});

/// State of the Library tab: the joined items, category tabs, the query and
/// the multi-selection. Every write goes through the decorated repositories.
class LibraryController extends ChangeNotifier {
  /// Creates the controller; call [start] to subscribe. `schedule` runs
  /// the coalesced notify later: the screen passes [beforeNextFrame], the
  /// default (unit tests, no binding) is the next event-loop turn.
  new(this.deps, {this._schedule = nextTurn}) {
    _facts = FactsTracker(deps, _dataChanged);
  }

  final NotifyScheduler _schedule;

  /// Repositories, ports and clock.
  final LibraryDeps deps;
  late final FactsTracker _facts;
  SourceAvailability? _sources;
  final _subs = <StreamSubscription<Object?>>[];

  Map<MangaKey, LibraryEntry> _entries = {};
  Map<MangaKey, Set<String>> _membership = {};
  List<Category> _categories = const [];
  Set<String> _liveIds = const {};
  LibraryQuery _query = const LibraryQuery();
  final Set<MangaKey> _selected = {};
  bool _selecting = false;
  bool _loaded = false;
  List<LibraryItem>? _items;
  List<LibraryItem>? _visible;
  bool _notifyPending = false;
  bool _disposed = false;

  /// Whether the library has been read once.
  bool get loaded => _loaded;

  /// Live categories by order: the tabs after "Default".
  List<Category> get categories => _categories;

  /// Whether "Default" shows: pre-load, no categories, or an uncategorised one.
  bool get hasDefaultTab =>
      !_loaded ||
      _categories.isEmpty ||
      items.any((i) => i.categoryIds.isEmpty);

  /// The tab on screen: the query's, but a hidden "Default" falls through
  /// to the first category (the query keeps `null`, so it comes back).
  String? get tab =>
      _query.categoryId ?? (hasDefaultTab ? null : _categories.first.id);

  /// Current tab, filters, search and sort.
  LibraryQuery get query => _query;
  set query(LibraryQuery q) {
    _query = q;
    _visible = null;
    notifyListeners();
  }

  /// Every entry joined with its facts, unsorted; rebuilt once per change.
  List<LibraryItem> get items =>
      _items ??= List.unmodifiable([for (final e in _entries.values) _item(e)]);

  /// [items] after [query]; recomputed only after a change, not per read.
  List<LibraryItem> get visible => _visible ??= List.unmodifiable(
    applyQuery(items, tab == null ? _query : _query.copyWith(categoryId: tab)),
  );

  /// Stream-driven changes (4 fact streams per entry, the repositories,
  /// source availability): the cached lists are dropped at once, and one
  /// notify covers everything that arrives in this event-loop turn, so a
  /// cold start of N entries is not ~4N rebuild requests.
  void _dataChanged() {
    _items = null;
    _visible = null;
    if (_disposed || _notifyPending) return;
    _notifyPending = true;
    _schedule(() {
      _notifyPending = false;
      if (!_disposed) notifyListeners();
    });
  }

  /// Whether multi-select mode is on.
  bool get selecting => _selecting;

  /// Selected keys.
  Set<MangaKey> get selected => Set.unmodifiable(_selected);

  /// Subscribes to the repositories.
  void start() {
    final repos = deps.repos;
    _sources = SourceAvailability(deps.sourceProviders, _dataChanged);
    _subs
      ..add(repos.library.watch().listen(_onEntries))
      ..add(repos.categories.watch().listen(_onCategories))
      ..add(
        repos.categories.watchMembership().listen((m) {
          _membership = m;
          _dataChanged();
        }),
      );
  }

  void _onEntries(List<LibraryEntry> entries) {
    _entries = {for (final e in entries) e.key: e};
    _selected.retainAll(_entries.keys);
    _facts.track(_entries.keys.toSet());
    _loaded = true;
    _dataChanged();
  }

  void _onCategories(List<Category> categories) {
    _categories = categories;
    _liveIds = {for (final c in categories) c.id};
    final tab = _query.categoryId;
    if (tab != null && !categories.any((c) => c.id == tab)) {
      _query = _query.copyWith(clearCategory: true);
    }
    _dataChanged();
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
      // Memberships of deleted categories would hide it from "Default".
      categoryIds: (_membership[e.key] ?? const {}).intersection(_liveIds),
      sourceAvailable: _sources?.isAvailable(e.sourceId) ?? true,
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

  /// Applies [changes] (category id to member) to every selected entry,
  /// then ends the selection: moved entries may have left the tab.
  Future<void> setCategories(Map<String, bool> changes) async {
    final keys = _selected.toList();
    clearSelection();
    for (final key in keys) {
      for (final MapEntry(key: id, value: member) in changes.entries) {
        await deps.repos.categories.setMembership(key, id, member);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_facts.dispose());
    unawaited(_sources?.dispose());
    super.dispose();
  }
}
