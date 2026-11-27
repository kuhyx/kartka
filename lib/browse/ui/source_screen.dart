import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/paged_controller.dart';
import 'package:kartka/browse/state/typed_listings.dart';
import 'package:kartka/browse/ui/challenge_prompt.dart';
import 'package:kartka/browse/ui/content_type_toggle.dart';
import 'package:kartka/browse/ui/manga_grid.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/challenge.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:material_ui/material_ui.dart';

/// One source: Popular / Latest / Search tabs, each an infinite grid of
/// the content types the toggle allows (a mark when the source cannot).
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
            body: const EmptyMark(
              icon: Icons.cloud_off_outlined,
              semanticLabel: 'Source unavailable',
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
  late final _listings = TypedListings(
    widget.source,
    BrowseScope.of(context).contentType..addListener(_retype),
  );
  late final PagedController<MangaSummary> _popular = _paged(
    _listings.fetcher(Listing.popular),
  );
  late final PagedController<MangaSummary> _latest = _paged(
    _listings.fetcher(Listing.latest),
  );
  late final PagedController<MangaSummary> _search = _paged(
    _searchFetch(widget.query ?? ''),
  );
  late final _queryField = TextEditingController(text: widget.query);
  late String? _active = (widget.query ?? '').isEmpty ? null : widget.query;

  void _submit(String raw) {
    final q = raw.trim();
    if (q.isEmpty) return;
    setState(() => _active = q);
    unawaited(_search.reset(fetch: _yielding(_searchFetch(q))));
  }

  /// A new content type reloads what was already fetched; the other grids
  /// read the setting when they first load.
  void _retype() {
    for (final c in [_popular, _latest, if (_active != null) _search]) {
      if (c.pagesLoaded > 0 || c.loading || c.error != null) {
        unawaited(c.reset());
      }
    }
  }

  PagedController<MangaSummary> _paged(PageFetcher<MangaSummary> fetch) =>
      PagedController<MangaSummary>(
        _yielding(fetch),
        keyOf: (m) => m.url,
        onError: _report,
      );

  // A page fetch goes before queued covers (89e1ec6e): they share the
  // server's rate limiter for this source.
  PageFetcher<MangaSummary> _yielding(PageFetcher<MangaSummary> fetch) =>
      (page) {
        final result = fetch(page);
        if (mounted) BrowseScope.of(context).coversYieldTo?.call(result);
        return result;
      };

  /// A failed page (the grid's Retry screen) goes to the diagnostics log.
  void _report(Object error, StackTrace stack) {
    if (!mounted) return;
    final log = BrowseScope.of(context).diagnostics;
    if (log == null) return;
    ErrorReporter.of(log).report(
      'browse.page',
      error,
      stack: stack,
      sourceId: widget.source.ref.id,
    );
  }

  PageFetcher<MangaSummary> _searchFetch(String q) =>
      _listings.fetcher(Listing.search, q);

  @override
  void dispose() {
    _listings.type.removeListener(_retype);
    _listings.dispose();
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
          actions: [
            Builder(
              builder: (context) {
                final tab = DefaultTabController.of(context);
                return ListenableBuilder(
                  listenable: Listenable.merge([tab, _listings.applied]),
                  builder: (_, _) => ContentTypeToggle(
                    BrowseScope.of(context).contentType,
                    applied: _listings.appliedTo(Listing.values[tab.index]),
                  ),
                );
              },
            ),
            if (widget.source case final WebViewTarget site)
              IconButton(
                icon: const Icon(
                  Icons.open_in_browser,
                  semanticLabel: 'Open in WebView',
                ),
                tooltip: 'WebView',
                onPressed: () => unawaited(
                  openInWebView(
                    context,
                    BrowseScope.of(context).browser,
                    site.webViewUrl,
                  ),
                ),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(
                  Icons.local_fire_department,
                  semanticLabel: 'Popular',
                ),
              ),
              Tab(
                icon: Icon(
                  Icons.new_releases_outlined,
                  semanticLabel: 'Latest',
                ),
              ),
              Tab(icon: Icon(Icons.search, semanticLabel: 'Search')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            PagedMangaGrid(_popular, empty: _empty(context)),
            PagedMangaGrid(_latest, empty: _empty(context)),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: TextField(
                    key: const ValueKey('source-search'),
                    controller: _queryField,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(
                        Icons.search,
                        semanticLabel: 'Search this source',
                      ),
                    ),
                    onSubmitted: _submit,
                  ),
                ),
                Expanded(
                  child: _active == null
                      ? const SizedBox.shrink()
                      : PagedMangaGrid(_search, empty: _empty(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A listing's empty state: the no-type hint, else "nothing here".
Widget _empty(BuildContext context) => TypedEmptyMark(
  BrowseScope.of(context).contentType,
  orElse: const EmptyMark(
    icon: Icons.search_off,
    semanticLabel: 'Nothing here',
  ),
);
