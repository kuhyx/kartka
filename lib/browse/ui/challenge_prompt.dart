import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/platform/browser_engine.dart';

/// Shown instead of a plain error when a site answered with a browser
/// challenge (docs/DOCS-contracts-webview.md §2, §7). Kartka never solves
/// it: kuhy opens the site, passes the check or logs in, then it retries.
class ChallengePrompt extends StatelessWidget {
  /// Prompt for [challenge]; [onRetry] runs after the WebView closes.
  const new(this.challenge, {required this.onRetry, super.key});

  /// What the site answered with.
  final ChallengeRequired challenge;

  /// Loads again.
  final VoidCallback onRetry;

  Future<void> _open(BuildContext context) async {
    final browser = BrowseScope.of(context).browser;
    if (await openInWebView(context, browser, challenge.url)) onRetry();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 40,
          semanticLabel: 'Browser check: ${challenge.kind}',
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(challenge.url.host, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.md),
        IconButton.filled(
          iconSize: 32,
          onPressed: () => unawaited(_open(context)),
          icon: const Icon(
            Icons.open_in_browser,
            semanticLabel: 'Open in WebView',
          ),
        ),
      ],
    ),
  );
}

/// Opens [url] for kuhy: the in-app WebView page (Android) or the
/// external Kartka browser window plus a "Done" dialog (desktop). Then
/// [KartkaBrowser.finish] makes the site's cookies apply. Returns whether
/// it finished; a missing engine shows a snackbar instead.
Future<bool> openInWebView(
  BuildContext context,
  KartkaBrowser browser,
  Uri url,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  try {
    if (browser.inApp) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => _WebViewPage(browser, url)),
      );
    } else {
      await browser.openExternal(url);
      if (!context.mounted) return false;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Icon(
            Icons.open_in_browser,
            size: 48,
            semanticLabel: 'Finish in the browser window',
          ),
          content: Text(url.host, textAlign: TextAlign.center),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Icon(Icons.check, semanticLabel: 'Done'),
            ),
          ],
        ),
      );
    }
    await browser.finish(url);
    return true;
  } on EngineUnavailable catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Icon(
          Icons.error_outline,
          color: errorColor,
          semanticLabel: 'Browser engine unavailable: ${e.reason}',
        ),
      ),
    );
    return false;
  }
}

/// The full-screen in-app WebView; leaving it in any way counts as done.
class _WebViewPage extends StatelessWidget {
  const new(this.browser, this.url);

  final KartkaBrowser browser;
  final Uri url;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(url.host),
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.check, semanticLabel: 'Done'),
        ),
      ],
    ),
    body: browser.buildView(url),
  );
}
