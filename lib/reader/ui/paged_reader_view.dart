import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/reader/logic/chapter_strip.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/ui/reader_view_controller.dart';
import 'package:kartka/reader/ui/zoomable_page.dart';

/// Builds the content of one strip slot.
typedef SlotBuilder = Widget Function(BuildContext context, StripSlot slot);

/// Reports a tap at [position] inside a viewport of [size].
typedef ViewTap = void Function(Offset position, Size size);

/// One page per screen: LTR, RTL or vertical, with zoomable pages.
class PagedReaderView extends StatefulWidget {
  /// A pager over [strip] starting at [initialItem].
  const new({
    required this.mode,
    required this.strip,
    required this.initialItem,
    required this.slotBuilder,
    required this.onItemChanged,
    required this.controller,
    required this.onTap,
    super.key,
  });

  /// The paged mode to lay out (axis and direction).
  final ReaderMode mode;

  /// The chapter's pages framed by transitions.
  final ChapterStrip strip;

  /// The list item shown first.
  final int initialItem;

  /// Builds page images and transition screens.
  final SlotBuilder slotBuilder;

  /// Called when the user settles on another item.
  final ValueChanged<int> onItemChanged;

  /// Receives navigation commands from the screen.
  final ReaderViewController controller;

  /// Single taps, for tap zones.
  final ViewTap onTap;

  @override
  State<PagedReaderView> createState() => _PagedReaderViewState();
}

class _PagedReaderViewState extends State<PagedReaderView>
    implements ReaderViewHandle {
  late final PageController _pages = PageController(
    initialPage: widget.initialItem,
  );
  bool _zoomed = false;
  late final void Function() _detach;

  @override
  void initState() {
    super.initState();
    _detach = widget.controller.attach(this);
  }

  @override
  void dispose() {
    _detach();
    _pages.dispose();
    super.dispose();
  }

  int get _current => _pages.page?.round() ?? widget.initialItem;

  @override
  void step(int delta) => jumpToItem(_current + delta, animate: true);

  @override
  void jumpToItem(int item, {bool animate = false}) {
    final target = item.clamp(0, widget.strip.itemCount - 1);
    if (!_pages.hasClients) return;
    if (animate) {
      _pages
          .animateToPage(
            target,
            duration: AppDuration.base,
            curve: AppCurve.standard,
          )
          .ignore();
    } else {
      _pages.jumpToPage(target);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      return PageView.builder(
        controller: _pages,
        scrollDirection: widget.mode.axis,
        reverse: widget.mode.reversed,
        physics: _zoomed
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        itemCount: widget.strip.itemCount,
        onPageChanged: (item) {
          setState(() => _zoomed = false);
          widget.onItemChanged(item);
        },
        itemBuilder: (context, item) {
          final slot = widget.strip.slotAt(item);
          final content = widget.slotBuilder(context, slot);
          void tap(Offset p) => widget.onTap(p, size);
          if (!slot.isPage) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => tap(d.localPosition),
              child: content,
            );
          }
          return ZoomablePage(
            onTap: tap,
            onZoomChanged: (z) => setState(() => _zoomed = z),
            child: SizedBox.expand(child: content),
          );
        },
      );
    },
  );
}
