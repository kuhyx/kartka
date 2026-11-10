import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/ui/spoken_label.dart';

/// Label and icon of each shell tab, in [KartkaTab] order (the destinations
/// must line up with the router's branches).
const Map<KartkaTab, ({IconData icon, String semanticLabel})> tabInfo = {
  KartkaTab.library: (
    icon: Icons.collections_bookmark,
    semanticLabel: 'Library',
  ),
  KartkaTab.updates: (icon: Icons.new_releases, semanticLabel: 'Updates'),
  KartkaTab.browse: (icon: Icons.explore, semanticLabel: 'Browse'),
  KartkaTab.sources: (icon: Icons.insights, semanticLabel: 'Sources'),
  KartkaTab.more: (icon: Icons.more_horiz, semanticLabel: 'More'),
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
                // The rail keeps each label invisible, for semantics only.
                labelType: NavigationRailLabelType.none,
                destinations: [
                  for (final t in tabs)
                    NavigationRailDestination(
                      icon: Icon(t.icon),
                      label: Text(t.semanticLabel),
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
        // Labels stay spoken only: hidden, and no long-press tooltip.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              label: t.semanticLabel,
              tooltip: '',
            ),
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
  Widget build(BuildContext context) => EmptyMark(
    icon: tabInfo[tab]!.icon,
    semanticLabel: '${tabInfo[tab]!.semanticLabel} is not built yet',
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
      return const EmptyMark(
        icon: Icons.settings,
        semanticLabel: 'Nothing to configure yet',
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [for (final tile in tiles) tile(context)],
    );
  }
}
