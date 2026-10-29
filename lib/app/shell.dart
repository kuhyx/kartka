import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';

/// Label and icon of each shell tab, in [KartkaTab] order (the destinations
/// must line up with the router's branches).
const Map<KartkaTab, ({String label, IconData icon})> tabInfo = {
  KartkaTab.library: (label: 'Library', icon: Icons.collections_bookmark),
  KartkaTab.updates: (label: 'Updates', icon: Icons.new_releases),
  KartkaTab.browse: (label: 'Browse', icon: Icons.explore),
  KartkaTab.sources: (label: 'Sources', icon: Icons.insights),
  KartkaTab.more: (label: 'More', icon: Icons.more_horiz),
};

/// Width at which the bottom bar becomes a side rail (M3 "medium").
const railBreakpoint = 840.0;

/// The app frame: bottom navigation on phones, a rail on wide windows.
///
/// Every tab starts below the status bar (a tab's own AppBar then sees no
/// top inset, so nothing is padded twice).
///
/// Both are Material navigation widgets, so every tab is a focus stop and
/// activates with Enter/Space (DOCS-operability rule 1-2).
class KartkaShell extends StatelessWidget {
  /// Frames [shell]'s current branch.
  const new({required this.shell, super.key});

  /// go_router's branch navigator.
  final StatefulNavigationShell shell;

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= railBreakpoint;
    final tabs = [for (final t in KartkaTab.values) tabInfo[t]!];
    if (wide) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: shell.currentIndex,
                onDestinationSelected: _go,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final t in tabs)
                    NavigationRailDestination(
                      icon: Icon(t.icon),
                      label: Text(t.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: shell),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      // The bar keeps the bottom inset; the tabs only lose the top one.
      body: SafeArea(bottom: false, child: shell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}

/// Shown for a tab no feature has filled yet.
class TabPlaceholder extends StatelessWidget {
  /// Placeholder for [tab].
  const new(this.tab, {super.key});

  /// The unfilled tab.
  final KartkaTab tab;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: tabInfo[tab]!.icon,
    title: '${tabInfo[tab]!.label} is not built yet',
    message: 'A feature part fills this tab through the registry.',
  );
}

/// The More tab: every feature's settings tiles, in registry order.
class MoreTab extends StatelessWidget {
  /// Lists [tiles].
  const new({required this.tiles, super.key});

  /// Tile builders from the registry.
  final List<WidgetBuilder> tiles;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) {
      return const EmptyState(
        icon: Icons.settings,
        title: 'Nothing to configure yet',
        message: 'Settings appear here as features land.',
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [for (final tile in tiles) tile(context)],
    );
  }
}
