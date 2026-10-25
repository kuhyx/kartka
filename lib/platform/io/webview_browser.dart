// coverage:ignore-file
// Thin wiring of webview_flutter and a platform channel, which only run on
// a device. The logic they feed (EngineCore, WebViewHosts,
// CookieKartkaHttp) is unit-tested on the VM; the coordinator verifies this
// file on the phone (docs/DOCS-contracts-webview.md §5).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kartka/platform/browser_engine.dart';
import 'package:kartka/platform/cookie_http.dart';
import 'package:kartka/platform/engine_core.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// `MainActivity`'s channel onto the WebView `CookieManager`.
const _cookies = MethodChannel('kartka/webview_cookies');

/// The `Cookie` header the WebView would send to [url] (raw, so values
/// containing `=` and HttpOnly cookies survive).
Future<String?> webViewCookieFor(Uri url) =>
    _cookies.invokeMethod<String>('getCookie', '$url');

/// [KartkaBrowser] on Android WebViews.
class WebViewBrowser implements KartkaBrowser {
  /// Registers finished hosts in [hosts].
  new(this.hosts) {
    _core = EngineCore(_open);
  }

  /// Hosts whose cookies kartka's HTTP carries.
  final WebViewHosts hosts;

  late final EngineCore _core;
  final _hidden = ValueNotifier<List<WebViewController>>(const []);

  Future<EnginePage> _open() async {
    final c = WebViewController();
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    _hidden.value = [..._hidden.value, c];
    return _WebViewPage(c, () {
      _hidden.value = [
        for (final o in _hidden.value)
          if (!identical(o, c)) o,
      ];
    });
  }

  @override
  Future<EngineResult> load(EngineRequest request) => _core.load(request);

  @override
  bool get inApp => true;

  @override
  Widget buildView(Uri url) => _InteractiveView(url);

  @override
  Future<void> openExternal(Uri url) async =>
      throw const EngineUnavailable('Android opens the WebView in the app');

  @override
  Future<void> finish(Uri url) async {
    await _cookies.invokeMethod<void>('flush');
    await hosts.add(url);
  }

  @override
  Widget host(Widget child) => ValueListenableBuilder(
    valueListenable: _hidden,
    builder: (_, controllers, _) => Stack(
      textDirection: TextDirection.ltr,
      children: [
        Positioned.fill(child: child),
        // webview_flutter has no headless mode: each load mounts a 1x1,
        // input-blind WebView so the page lays out and runs its timers.
        for (final c in controllers)
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: IgnorePointer(child: WebViewWidget(controller: c)),
          ),
      ],
    ),
  );
}

class _WebViewPage implements EnginePage {
  new(this.c, this.onClose);

  final WebViewController c;
  final VoidCallback onClose;

  @override
  Future<void> navigate(Uri url, Map<String, String> headers) =>
      c.loadRequest(url, headers: headers);

  @override
  Future<Object?> evaluate(String js) => c.runJavaScriptReturningResult(js);

  @override
  Future<void> close() async {
    onClose();
    await c.loadRequest(Uri.parse('about:blank'));
  }
}

class _InteractiveView extends StatefulWidget {
  const new(this.url);

  final Uri url;

  @override
  State<_InteractiveView> createState() => _InteractiveViewState();
}

class _InteractiveViewState extends State<_InteractiveView> {
  final _c = WebViewController();

  @override
  void initState() {
    super.initState();
    // The WebView's own User-Agent: never replaced (contract §2).
    unawaited(
      _c
          .setJavaScriptMode(JavaScriptMode.unrestricted)
          .then((_) => _c.loadRequest(widget.url)),
    );
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _c);
}
