import 'package:material_ui/material_ui.dart';

/// The category tab bar, driven by [index] so a tap and a filter change
/// animate the same indicator. Owns its [TabController] and replaces it only
/// when the number of tabs changes.
class CategoryTabs extends StatefulWidget implements PreferredSizeWidget {
  /// Creates the bar over [labels]; a null label is the "Default" tab.
  const new({
    required this.labels,
    required this.index,
    required this.onSelect,
    super.key,
  });

  /// Category names in order; null for "Default" (drawn as a glyph).
  final List<String?> labels;

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
    tabs: [
      for (final l in widget.labels)
        if (l == null)
          const Tab(icon: Icon(Icons.inbox, semanticLabel: 'Default'))
        else
          Tab(text: l),
    ],
  );
}
