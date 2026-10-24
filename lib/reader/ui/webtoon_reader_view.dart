import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/reader/logic/chapter_strip.dart';
import 'package:kartka/reader/logic/webtoon_position.dart';
import 'package:kartka/reader/ui/paged_reader_view.dart';
import 'package:kartka/reader/ui/reader_view_controller.dart';
import 'package:kartka/reader/ui/zoomable_page.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Continuous vertical scroll of every page, zoomable as a whole.
class WebtoonReaderView extends StatefulWidget {
  /// A continuous list over [strip] starting at [initialItem].
  const new({
    required this.strip,
    required this.initialItem,
    required this.slotBuilder,
    required this.onItemChanged,
    required this.controller,
    required this.onTap,
    super.key,
  });

  /// The chapter's pages framed by transitions.
  final ChapterStrip strip;

  /// The list item shown first.
  final int initialItem;

  /// Builds page images and transition screens.
  final SlotBuilder slotBuilder;

  /// Called when another item becomes current.
  final ValueChanged<int> onItemChanged;

  /// Receives navigation commands from the screen.
  final ReaderViewController controller;

  /// Single taps, for tap zones.
  final ViewTap onTap;

  /// Fraction of the viewport one step scrolls, leaving context to re-find
  /// your place.
  static const double stepFraction = 0.85;

  @override
  State<WebtoonReaderView> createState() => _WebtoonReaderViewState();
}

class _WebtoonReaderViewState extends State<WebtoonReaderView>
    implements ReaderViewHandle {
  final _items = ItemScrollController();
  final _offsets = ScrollOffsetController();
  final _positions = ItemPositionsListener.create();
  late final void Function() _detach;
  double _viewportHeight = 0;
  int? _current;

  @override
  void initState() {
    super.initState();
    _detach = widget.controller.attach(this);
    _positions.itemPositions.addListener(_onPositions);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositions);
    _detach();
    super.dispose();
  }

  void _onPositions() {
    final item = currentWebtoonItem([
      for (final p in _positions.itemPositions.value)
        (
          index: p.index,
          leading: p.itemLeadingEdge,
          trailing: p.itemTrailingEdge,
        ),
    ]);
    if (item == null || item == _current) return;
    _current = item;
    widget.onItemChanged(item);
  }

  @override
  void step(int delta) {
    if (!_items.isAttached) return;
    _offsets
        .animateScroll(
          offset: delta * _viewportHeight * WebtoonReaderView.stepFraction,
          duration: AppDuration.base,
          curve: AppCurve.standard,
        )
        .ignore();
  }

  @override
  void jumpToItem(int item) {
    if (!_items.isAttached) return;
    _items.jumpTo(index: item.clamp(0, widget.strip.itemCount - 1));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      _viewportHeight = size.height;
      return ZoomablePage(
        onTap: (p) => widget.onTap(p, size),
        child: ScrollablePositionedList.builder(
          itemCount: widget.strip.itemCount,
          initialScrollIndex: widget.initialItem,
          itemScrollController: _items,
          scrollOffsetController: _offsets,
          itemPositionsListener: _positions,
          itemBuilder: (context, item) =>
              widget.slotBuilder(context, widget.strip.slotAt(item)),
        ),
      );
    },
  );
}
