import 'package:flutter/widgets.dart';
import 'package:kartka/platform/browser_engine.dart';

/// [KartkaBrowser] for tests: answers loads from a handler and records the
/// interactive flow.
class FakeBrowser implements KartkaBrowser {
  /// Answers loads with [onLoad] (default: an empty page at the URL).
  new({this.onLoad, this.inApp = false});

  /// Load handler; may throw (e.g. [ChallengeRequired]).
  final Future<EngineResult> Function(EngineRequest request)? onLoad;

  @override
  final bool inApp;

  /// Every load request, in order.
  final List<EngineRequest> loads = [];

  /// Every URL opened with [openExternal].
  final List<Uri> opened = [];

  /// Every URL passed to [finish].
  final List<Uri> finished = [];

  @override
  Future<EngineResult> load(EngineRequest request) async {
    loads.add(request);
    return await onLoad?.call(request) ??
        EngineResult(url: request.url, html: '');
  }

  @override
  Widget buildView(Uri url) => const Placeholder();

  @override
  Future<void> openExternal(Uri url) async => opened.add(url);

  @override
  Future<void> finish(Uri url) async => finished.add(url);

  @override
  Widget host(Widget child) => child;
}
