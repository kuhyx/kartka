import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Tells the page image inside a [ZoomablePage] whether it is zoomed in, so
/// it can decode at the larger size only then.
class ZoomScope extends InheritedWidget {
  /// Scopes [zoomed] over [child].
  const new({required this.zoomed, required super.child, super.key});

  /// Whether the page is zoomed past 1x.
  final bool zoomed;

  /// Whether the nearest [ZoomablePage] above [context] is zoomed in.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ZoomScope>()?.zoomed ?? false;

  @override
  bool updateShouldNotify(ZoomScope oldWidget) => oldWidget.zoomed != zoomed;
}

/// A page that zooms with pinch and double tap and reports single taps.
///
/// Single taps are forwarded as positions inside the page so the caller can
/// resolve tap zones. [onZoomChanged] fires when the page leaves or returns
/// to 1x, so a pager can stop swiping while the user pans a zoomed page.
class ZoomablePage extends StatefulWidget {
  /// Wraps [child] with zoom gestures.
  const new({required this.child, this.onTap, this.onZoomChanged, super.key});

  /// The page content.
  final Widget child;

  /// Called with the tap position for single taps.
  final ValueChanged<Offset>? onTap;

  /// Called with true when zoomed in, false when back to 1x.
  final ValueChanged<bool>? onZoomChanged;

  /// Scale a double tap zooms to.
  static const double doubleTapScale = 2.5;

  @override
  State<ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<ZoomablePage>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: AppDuration.base,
  );
  Animation<Matrix4>? _tween;
  Offset _doubleTapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _animation.addListener(() {
      final tween = _tween;
      if (tween != null) _transform.value = tween.value;
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _report() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged?.call(zoomed);
  }

  void _toggleZoom() {
    final Matrix4 target;
    if (_zoomed) {
      target = Matrix4.identity();
    } else {
      const s = ZoomablePage.doubleTapScale;
      final p = _doubleTapAt;
      // Scale around the tapped point: translate so it stays under the finger.
      target = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _tween = Matrix4Tween(
      begin: _transform.value,
      end: target,
    ).animate(CurvedAnimation(parent: _animation, curve: AppCurve.standard));
    _animation.forward(from: 0).whenComplete(_report).ignore();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapUp: (d) => widget.onTap?.call(d.localPosition),
    onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
    onDoubleTap: _toggleZoom,
    child: InteractiveViewer(
      transformationController: _transform,
      maxScale: 5,
      onInteractionEnd: (_) => _report(),
      child: ZoomScope(zoomed: _zoomed, child: widget.child),
    ),
  );
}
