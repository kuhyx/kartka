import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/paged_controller.dart';
import 'package:kartka/browse/ui/manga_grid.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';

/// One source: Popular / Latest / Search tabs, each an infinite grid.
class SourceScreen extends StatelessWidget {
  /// Creates the screen for [sourceId], on the Search tab when [query] set.
  const new(this.sourceId, {this.query, super.key});

  /// Source id from the route.
  final String sourceId;

  /// Initial search query.
  final String? query;

  @override
  Widget build(BuildContext context) {
    final deps = BrowseScope.of(context);
    return StreamBuilder<List<MangaSource>>(
      stream: deps.sources.watch(),
      initialData: deps.sources.current,
      builder: (context, _) {
        final source = deps.sources.byId(sourceId);
        if (source == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Source unavailable',
              message: 'It is not installed or its server is unreachable.',
            ),
          );
        }
        return _SourceTabs(source, query: query);
      },
    );
  }
}

class _SourceTabs extends StatefulWidget {
  const new(this.source, {this.query});

  final MangaSource source;
  final String? query;

  @override
  State<_SourceTabs> createState() => _SourceTabsState();
}

class _SourceTabsState extends State<_SourceTabs> {
  late final PagedController<MangaSummary> _popular = _paged(
    widget.source.popular,
  );
  late final PagedController<MangaSummary> _latest = _paged(
    widget.source.latest,
  );
  late final PagedController<MangaSummary> _search = PagedController(
    _searchFetch(widget.query ?? ''),
    keyOf: (m) => m.url,
  );
  late final _queryField = TextEditingController(text: widget.query);
  late String? _active = (widget.query ?? '').isEmpty ? null : widget.query;

  void _submit(String raw) {
    final q = raw.trim();
    if (q.isEmpty) return;
    setState(() => _active = q);
    unawaited(_search.reset(fetch: _searchFetch(q)));
  }

  static PagedController<MangaSummary> _paged(
    Future<SearchPage> Function(int) call,
  ) => PagedController<MangaSummary>((page) async {
    final p = await call(page);
    return (items: p.items, hasNext: p.hasNext);
  }, keyOf: (m) => m.url);

  PageFetcher<MangaSummary> _searchFetch(String q) => (page) async {
    final p = await widget.source.search(q, page);
    return (items: p.items, hasNext: p.hasNext);
  };

  @override
  void dispose() {
    _popular.dispose();
    _latest.dispose();
    _search.dispose();
    _queryField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: _active == null ? 0 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.source.ref.name),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Popular'),
              Tab(text: 'Latest'),
              Tab(text: 'Search'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            PagedMangaGrid(_popular),
            PagedMangaGrid(_latest),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: TextField(
                    key: const ValueKey('source-search'),
                    controller: _queryField,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      labelText: 'Search this source',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: _submit,
                  ),
                ),
                Expanded(
                  child: _active == null
                      ? const SizedBox.shrink()
                      : PagedMangaGrid(_search),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
