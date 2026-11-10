import 'package:flutter/material.dart';
import 'package:kartka/reader/logic/reader_mode.dart';

/// What a tap on the page does.
enum TapAction {
  /// Go one page back.
  previous,

  /// Go one page forward.
  next,

  /// Show or hide the reader controls.
  menu,
}

/// The configurable split of the viewport into tap regions.
enum TapZoneLayout {
  /// Left third back, right third forward, middle the menu.
  thirds('thirds', 'Left / right thirds'),

  /// Top band and left column back, bottom band and right column forward.
  lShape('l_shape', 'L-shaped'),

  /// Top band the menu, then left third back and the rest forward.
  kindle('kindle', 'Kindle'),

  /// No navigation taps; every tap toggles the menu.
  disabled('disabled', 'Off');

  new(this.id, this.label);

  /// Stable id used for persistence.
  final String id;

  /// Human-readable name, spoken (never painted) in settings.
  final String label;

  /// The glyph painted for the layout in settings.
  IconData get icon => switch (this) {
    thirds => Icons.view_column_outlined,
    lShape => Icons.border_style,
    kindle => Icons.view_agenda_outlined,
    disabled => Icons.do_not_touch_outlined,
  };

  /// The layout stored under [id], or null when unknown.
  static TapZoneLayout? fromId(String? id) {
    for (final l in values) {
      if (l.id == id) return l;
    }
    return null;
  }
}

/// Which screen side a region sits on before reading direction applies.
enum _Side { back, forward, menu }

/// Resolves a tap at [position] inside a viewport of [size].
///
/// Regions are drawn for left-to-right reading; [ReaderMode.pagedRtl] mirrors
/// them so the side you swipe towards is still "next". [invert] swaps
/// previous and next for people who prefer the opposite convention.
TapAction resolveTap({
  required TapZoneLayout layout,
  required Offset position,
  required Size size,
  required ReaderMode mode,
  bool invert = false,
}) {
  if (size.width <= 0 || size.height <= 0) return TapAction.menu;
  final x = position.dx / size.width;
  final y = position.dy / size.height;
  final side = _sideFor(layout, x, y);
  if (side == _Side.menu) return TapAction.menu;
  final flip = mode.reversed != invert;
  final forward = (side == _Side.forward) != flip;
  return forward ? TapAction.next : TapAction.previous;
}

_Side _sideFor(TapZoneLayout layout, double x, double y) {
  const third = 1 / 3;
  switch (layout) {
    case TapZoneLayout.thirds:
      if (x < third) return _Side.back;
      if (x > 2 * third) return _Side.forward;
      return _Side.menu;
    case TapZoneLayout.lShape:
      if (y < third) return _Side.back;
      if (y > 2 * third) return _Side.forward;
      if (x < third) return _Side.back;
      if (x > 2 * third) return _Side.forward;
      return _Side.menu;
    case TapZoneLayout.kindle:
      if (y < third) return _Side.menu;
      return x < third ? _Side.back : _Side.forward;
    case TapZoneLayout.disabled:
      return _Side.menu;
  }
}
