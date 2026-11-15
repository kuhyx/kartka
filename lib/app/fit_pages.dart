import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// design_system's `FitGrid` (v0.3.0) with two fixes the phone showed:
/// a gap above the page dots, so the last row's edge and shadow are not
/// cut, and a "3 / 65" counter once there are more pages than dots fit
/// across (a 778-manga library overflowed the dots row). Same contract:
/// square cells sized from the box, never a vertical scroll, overflow on
/// horizontal pages. Upstream the fixes to design_system and delete this.
class FitPages extends StatefulWidget {
  /// Creates the grid.
  const new({
    required this.itemCount,
    required this.itemBuilder,
    this.columns = 3,
    this.labelHeight = 0,
    this.minSquare = 1,
    this.spacing = AppSpacing.sm,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    super.key,
  });

  /// Number of items across all pages.
  final int itemCount;

  /// Builds item `index`, counted over all pages; fills the given cell.
  final IndexedWidgetBuilder itemBuilder;

  /// Cells per row.
  final int columns;

  /// Height reserved under each square, for a caption.
  final double labelHeight;

  /// Least square side, as a fraction of the column width.
  final double minSquare;

  /// Gap between cells, both ways, and above the page indicator.
  final double spacing;

  /// Space around the cells.
  final EdgeInsets padding;

  @override
  State<FitPages> createState() => _FitPagesState();
}

const double _dotSize = AppSpacing.sm;
const double _dotStep = _dotSize + 2 * AppSpacing.xs;
const double _dotsHeight = AppSpacing.md + AppSpacing.xs;

class _FitPagesState extends State<FitPages> {
  final _controller = PageController();
  var _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _indicator => _dotsHeight + widget.spacing;

  int _rowsFor(double height, double cellHeight) => math.max(
    1,
    ((height + widget.spacing) / (cellHeight + widget.spacing)).floor(),
  );

  int _pagesFor(int perPage) =>
      math.max(1, (widget.itemCount / perPage).ceil());

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = widget;
      final inner = box.maxWidth - w.padding.horizontal;
      final cellW = (inner - w.spacing * (w.columns - 1)) / w.columns;
      final height = box.maxHeight - w.padding.vertical;
      final minCellH = cellW * w.minSquare + w.labelHeight;
      var rows = _rowsFor(height, minCellH);
      if (_pagesFor(rows * w.columns) > 1) {
        rows = _rowsFor(height - _indicator, minCellH);
      }
      final perPage = rows * w.columns;
      final count = _pagesFor(perPage);
      final pageHeight = height - (count > 1 ? _indicator : 0);
      final cellH = math.max(
        minCellH,
        (pageHeight + w.spacing) / rows - w.spacing,
      );
      final current = math.min(_page, count - 1);
      return Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: count,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (context, p) => Padding(
                padding: w.padding,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: _pageOf(p * perPage, rows, Size(cellW, cellH)),
                ),
              ),
            ),
          ),
          if (count > 1) ...[
            SizedBox(height: w.spacing),
            SizedBox(
              height: _dotsHeight,
              child: count * _dotStep <= box.maxWidth
                  ? _Dots(count: count, current: current)
                  : Center(
                      child: Text(
                        '${current + 1} / $count',
                        key: const ValueKey<String>('fit-grid-pages'),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
            ),
          ],
        ],
      );
    },
  );

  Widget _pageOf(int first, int rows, Size cell) {
    final w = widget;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: w.spacing,
      children: [
        for (var r = 0; r < rows; r++)
          Row(
            spacing: w.spacing,
            children: [
              for (var c = 0; c < w.columns; c++)
                SizedBox.fromSize(
                  size: cell,
                  child: first + r * w.columns + c < w.itemCount
                      ? w.itemBuilder(context, first + r * w.columns + c)
                      : null,
                ),
            ],
          ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const new({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              key: ValueKey<String>('fit-grid-dot-$i'),
              width: _dotSize,
              height: _dotSize,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == current ? scheme.primary : scheme.outlineVariant,
              ),
            ),
        ],
      ),
    );
  }
}
