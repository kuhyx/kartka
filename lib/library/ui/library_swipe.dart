import 'package:flutter/material.dart';

/// Fling speed (logical px/s) that lets a shorter swipe switch a tab.
const double _flingVelocity = 1000;

/// A fling must still travel this share of the width (clamped to px), so a
/// quick touch never switches: ~100 px on a phone.
const double _flingShare = 0.25;
const double _flingMin = 48;
const double _flingMax = 160;

/// A slow drag must travel this share of the width (clamped to px).
const double _dragShare = 0.4;
const double _dragMin = 80;
const double _dragMax = 240;

/// Whether a horizontal swipe of [dx] px released at [velocity] px/s over
/// a [width] px wide area switches the tab.
bool swipeSwitches(double dx, double velocity, double width) {
  final distance = dx.abs();
  final fling =
      velocity.abs() >= _flingVelocity &&
      velocity.sign == dx.sign &&
      distance >= (width * _flingShare).clamp(_flingMin, _flingMax);
  return fling || distance >= (width * _dragShare).clamp(_dragMin, _dragMax);
}

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
    final dx = _dx;
    _dx = 0;
    final width = context.size?.width ?? 0;
    if (swipeSwitches(dx, d.primaryVelocity ?? 0, width)) {
      widget.onStep(dx < 0 ? 1 : -1);
    }
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
  /// Creates the bar over [labels] (the first is "Default" when shown).
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
