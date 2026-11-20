import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/shown_wait_watch.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/global_search_controller.dart';
import 'package:kartka/browse/ui/content_type_toggle.dart';
import 'package:kartka/browse/ui/manga_grid.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:material_ui/material_ui.dart';

/// Searches every source at once; one row of hits per source, each row
/// filling in as its source answers. The content-type toggle re-runs the
/// search; a source that cannot narrow its hits carries a mark.
class GlobalSearchScreen extends StatefulWidget {
  /// Creates the screen, searching [query] immediately when non-empty.
  const new({this.query = '', super.key});

  /// Initial query.
  final String query;

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  GlobalSearchController? _search;
  StreamSubscription<void>? _sources;
  late final _field = TextEditingController(text: widget.query);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_search != null) return;
    final deps = BrowseScope.of(context);
    final registry = deps.sources;
    final type = _type = deps.contentType..addListener(_retype);
    final c = GlobalSearchController(registry.current, type: () => type.value);
    _search = c;
    if (widget.query.trim().isNotEmpty) unawaited(c.search(widget.query));
    // Runtime sources (Suwayomi, plugins) join the running search live.
    _sources = registry.watch().listen((l) => unawaited(c.updateSources(l)));
  }

  Listenable? _type;

  void _retype() => unawaited(_search!.search(_search!.query));

  @override
  void dispose() {
    _type?.removeListener(_retype);
    unawaited(_sources?.cancel());
    _search?.dispose();
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = _search!;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const ValueKey('global-search'),
          controller: _field,
          autofocus: widget.query.isEmpty,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, semanticLabel: 'Search all sources'),
          ),
          onSubmitted: (q) => unawaited(search.search(q)),
        ),
        actions: [ContentTypeToggle(BrowseScope.of(context).contentType)],
      ),
      body: ListenableBuilder(
        listenable: search,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          children: [
            for (final r in search.results) _SourceRow(r, search.query),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const new(this.state, this.query);

  final SourceSearchState state;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget body;
    if (state.loading) {
      body = const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: ShownWaitWatch(
          operation: 'search.global',
          child: LinearProgressIndicator(),
        ),
      );
    } else if (state.error != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.error,
              semanticLabel: 'Failed',
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                redactUrlQueries('${state.error}'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      );
    } else if (state.items.isEmpty) {
      body = const EmptyMark(
        icon: Icons.search_off,
        semanticLabel: 'No results',
      );
    } else {
      body = SizedBox(
        height: 240,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (_, i) =>
              SizedBox(width: 128, child: MangaTile(state.items[i])),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(state.source.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!state.applied) const NotAppliedMark(),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () => unawaited(
            context.push(sourceRoute(state.source.id, query: query)),
          ),
        ),
        body,
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
