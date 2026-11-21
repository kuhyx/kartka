import 'dart:async';
import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/app/shown_wait_watch.dart';
import 'package:kartka/browse/state/paged_controller.dart';
import 'package:kartka/browse/ui/challenge_prompt.dart';
import 'package:kartka/browse/ui/cover_image.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/source/challenge.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:material_ui/material_ui.dart';

/// One manga cover + title; opens the detail route. A focus stop, so arrow
/// keys walk the grid and the grid scrolls to the focused tile.
class MangaTile extends StatelessWidget {
  /// Creates a tile for [manga].
  const new(this.manga, {super.key});

  /// The manga shown.
  final MangaSummary manga;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () =>
            unawaited(context.push(mangaRoute(manga.sourceId, manga.url))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: CoverImage(manga.coverUrl)),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text(
                manga.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Infinite-scroll grid over a [PagedController]: the next page loads when
/// the viewport nears the end (scrolling by wheel, drag, PageDown or arrow
/// focus alike). Failures show a Retry button instead of the spinner.
class PagedMangaGrid extends StatefulWidget {
  /// Creates the grid; loads the first page if nothing is loaded yet.
  const new(this.controller, {this.empty, super.key});

  /// Paging state.
  final PagedController<MangaSummary> controller;

  /// Shown when the listing is empty; null: a plain "nothing here" mark.
  final Widget? empty;

  @override
  State<PagedMangaGrid> createState() => _PagedMangaGridState();
}

class _PagedMangaGridState extends State<PagedMangaGrid> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoad);
    widget.controller.addListener(_afterChange);
    if (widget.controller.items.isEmpty) {
      unawaited(widget.controller.loadMore());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_afterChange);
    _scroll.dispose();
    super.dispose();
  }

  void _afterChange() {
    if (!mounted) return;
    setState(() {});
    // A first page shorter than the viewport never scrolls: keep filling.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoad());
  }

  void _maybeLoad() {
    final c = widget.controller;
    if (!mounted || !_scroll.hasClients || c.error != null) return;
    final pos = _scroll.position;
    // One whole page ahead: a source page can take seconds (MangaFire up to
    // 1.2 s on the server, more on the phone) and a fling covers two screens
    // in under a second, so the next page is asked for as soon as the user is
    // inside the last loaded one (89e1ec6e, bf7e99dc).
    final pages = math.max(1, c.pagesLoaded);
    final onePage = (pos.maxScrollExtent + pos.viewportDimension) / pages;
    final ahead = math.max(math.max(600, pos.viewportDimension * 2), onePage);
    if (pos.extentAfter < ahead) unawaited(c.loadMore());
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (c.items.isEmpty && !c.hasNext && c.error == null) {
      return widget.empty ??
          const EmptyMark(
            icon: Icons.search_off,
            semanticLabel: 'Nothing here',
          );
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.md),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 168,
              childAspectRatio: 0.56,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
            ),
            itemCount: c.items.length,
            itemBuilder: (_, i) => MangaTile(c.items[i]),
          ),
        ),
        SliverToBoxAdapter(child: _Footer(c)),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const new(this.c);

  final PagedController<MangaSummary> c;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    final error = c.error;
    if (error is ChallengeRequired) {
      child = ChallengePrompt(error, onRetry: c.loadMore);
    } else if (error != null) {
      child = Column(
        children: [
          const Icon(Icons.error_outline, semanticLabel: 'Could not load'),
          Text(redactUrlQueries('$error'), textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          IconButton(
            iconSize: 32,
            onPressed: c.loadMore,
            icon: const Icon(Icons.refresh, semanticLabel: 'Retry'),
          ),
        ],
      );
    } else if (c.hasNext) {
      if (c.loading) {
        child = ShownWaitWatch(
          key: ValueKey(c.pagesLoaded),
          operation: 'browse.nextpage',
          child: const CircularProgressIndicator(),
        );
      } else {
        child = const SizedBox.square(dimension: 36);
      }
    } else {
      return const SizedBox(height: AppSpacing.lg);
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(child: child),
    );
  }
}
