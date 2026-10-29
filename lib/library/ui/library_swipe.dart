import 'package:flutter/material.dart';

/// Fling speed (logical px/s) that switches a tab regardless of distance.
const double _flingVelocity = 300;

/// Drag distance (logical px) that switches a tab even when released slowly.
const double _dragDistance = 80;

/// The tab [step] (+1 right, -1 left) away from [index] among [count]
/// tabs, wrapping at both ends. With fewer than two tabs it stays put.
int wrapIndex(int index, int step, int count) =>
    count < 2 ? index : (index + step) % count;

/// Turns a horizontal swipe on [child] into a tab step: a finger moving
/// right-to-left calls [onStep] with +1 (next tab), left-to-right with -1.
///
/// Only the horizontal-drag recogniser is added, so the child's vertical
/// scroll still wins the arena for vertical gestures, and the child is
/// never rebuilt by the gesture itself.
class CategorySwipe extends StatefulWidget {
  /// Wraps [child].
  const new({required this.onStep, required this.child, super.key});

  /// Called with +1 or -1 when a swipe crosses the threshold.
  final ValueChanged<int> onStep;

  /// The swiped content (the grid).
  final Widget child;

  @override
  State<CategorySwipe> createState() => _CategorySwipeState();
}

class _CategorySwipeState extends State<CategorySwipe> {
  double _dx = 0;

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final signal = v.abs() >= _flingVelocity
        ? v
        : (_dx.abs() >= _dragDistance ? _dx : 0.0);
    _dx = 0;
    if (signal != 0) widget.onStep(signal < 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) => _dx = 0,
    onHorizontalDragUpdate: (d) => _dx += d.primaryDelta ?? 0,
    onHorizontalDragEnd: _end,
    child: widget.child,
  );
}

/// The category tab bar, driven by [index] so a swipe and a tap animate
/// the same indicator. Owns its [TabController] and replaces it only when
/// the number of tabs changes.
class CategoryTabs extends StatefulWidget implements PreferredSizeWidget {
  /// Creates the bar over [labels] (the first is "All").
  const new({
    required this.labels,
    required this.index,
    required this.onSelect,
    super.key,
  });

  /// Tab labels in order.
  final List<String> labels;

  /// The selected tab.
  final int index;

  /// Called when a tab is tapped.
  final ValueChanged<int> onSelect;

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  State<CategoryTabs> createState() => _CategoryTabsState();
}

class _CategoryTabsState extends State<CategoryTabs>
    with TickerProviderStateMixin {
  late TabController _tabs = _make();

  TabController _make() => TabController(
    length: widget.labels.length,
    initialIndex: widget.index,
    vsync: this,
  );

  @override
  void didUpdateWidget(CategoryTabs old) {
    super.didUpdateWidget(old);
    if (widget.labels.length != _tabs.length) {
      _tabs.dispose();
      _tabs = _make();
    } else if (widget.index != _tabs.index) {
      _tabs.animateTo(widget.index);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TabBar(
    controller: _tabs,
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    onTap: widget.onSelect,
    tabs: [for (final l in widget.labels) Tab(text: l)],
  );
}
