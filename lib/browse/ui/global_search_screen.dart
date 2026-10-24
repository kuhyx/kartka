import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/global_search_controller.dart';
import 'package:kartka/browse/ui/manga_grid.dart';

/// Searches every source at once; one row of hits per source, each row
/// filling in as its source answers.
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
    final registry = BrowseScope.of(context).sources;
    final c = GlobalSearchController(registry.current);
    _search = c;
    if (widget.query.trim().isNotEmpty) unawaited(c.search(widget.query));
    // Runtime sources (Suwayomi, plugins) join the running search live.
    _sources = registry.watch().listen((l) => unawaited(c.updateSources(l)));
  }

  @override
  void dispose() {
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
          decoration: const InputDecoration(hintText: 'Search all sources'),
          onSubmitted: (q) => unawaited(search.search(q)),
        ),
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
        child: LinearProgressIndicator(),
      );
    } else if (state.error != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Text(
          'Failed: ${state.error}',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      );
    } else if (state.items.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Text('No results'),
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
          trailing: const Icon(Icons.chevron_right),
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
