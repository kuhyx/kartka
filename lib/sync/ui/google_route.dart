/// Which Google sign-in flow this build offers, and fetching its ID token.
///
/// crdt_sync_flutter covers Android (the plugin's account picker) but not
/// web, where Google Identity Services signs in only through its own
/// rendered button. Kartka's desktop app *is* the web build, so the web half
/// lives here: the button is shown in a dialog and its token is handed to
/// the same `signInWithGoogle` the Android path uses.
library;

import 'dart:async';
import 'dart:developer';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show googleIdToken;
import 'package:flutter/material.dart';
import 'package:kartka/sync/google_client.dart';
import 'package:kartka/sync/ui/gis_button.dart' as gis;

/// A Google sign-in flow.
enum GoogleRoute {
  /// The `google_sign_in` plugin's OS account picker (Android).
  plugin,

  /// The Google Identity Services button in a dialog (web / desktop).
  webButton,

  /// No flow: the screen shows a disabled button and why.
  none,
}

/// Picks the route for a platform. Pure, so the decision is testable on a
/// host that can run neither flow.
GoogleRoute googleRouteFor({
  required bool isWeb,
  required bool pluginSupported,
  required String clientId,
}) {
  // A button that can never succeed is worse than no button.
  if (clientId.isEmpty) return GoogleRoute.none;
  if (isWeb) return GoogleRoute.webButton;
  if (pluginSupported) return GoogleRoute.plugin;
  return GoogleRoute.none;
}

Future<String?> _pluginToken(String clientId) =>
    googleIdToken(serverClientId: clientId);

/// Where each route gets its token; tests replace the platform halves.
class GoogleTokenSources {
  /// Defaults reach the real plugin and the real GIS button.
  const new({
    this.plugin = _pluginToken,
    this.gisInit = gis.gisInitialize,
    this.gisButton = gis.gisButton,
    this.gisTokens = gis.gisIdTokens,
  });

  /// Android: the plugin's picker, for the Web client id as audience.
  final Future<String?> Function(String clientId) plugin;

  /// Web: one-time GIS initialisation.
  final Future<void> Function(String clientId) gisInit;

  /// Web: the rendered button.
  final Widget Function() gisButton;

  /// Web: tokens from button sign-ins.
  final Stream<String> Function() gisTokens;
}

/// Returns a Google ID token through [route], or null when there is none or
/// the user backs out (the caller then reports "cancelled").
Future<String?> fetchGoogleIdToken(
  BuildContext context,
  GoogleRoute route, {
  GoogleTokenSources sources = const GoogleTokenSources(),
  String clientId = kKartkaGoogleClientId,
}) async {
  switch (route) {
    case GoogleRoute.plugin:
      return await sources.plugin(clientId);
    case GoogleRoute.none:
      return null;
    case GoogleRoute.webButton:
      await sources.gisInit(clientId);
      if (!context.mounted) return null;
      return await showDialog<String>(
        context: context,
        builder: (_) => _GisDialog(
          button: sources.gisButton(),
          tokens: sources.gisTokens(),
        ),
      );
  }
}

/// Hosts the GIS button until it yields a token, fails, or is cancelled.
class _GisDialog extends StatefulWidget {
  const new({required this.button, required this.tokens});

  final Widget button;
  final Stream<String> tokens;

  @override
  State<_GisDialog> createState() => _GisDialogState();
}

class _GisDialogState extends State<_GisDialog> {
  // Subscribed in initState, before the button can render: a token that
  // arrived before the listener would otherwise be lost and the dialog hang.
  late final StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.tokens.listen(
      _close,
      onError: (Object error, StackTrace stackTrace) {
        // A configuration failure (origin not authorised) arrives here too,
        // so it is logged, not swallowed as "the user changed their mind".
        log(
          'Google sign-in did not complete',
          level: 900,
          error: error,
          stackTrace: stackTrace,
        );
        _close(null);
      },
    );
  }

  void _close(String? token) {
    if (mounted) Navigator.of(context).pop(token);
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sign in with Google'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Choose the sync account.'),
        const SizedBox(height: 16),
        SizedBox(height: 48, child: widget.button),
      ],
    ),
    actions: [
      TextButton(onPressed: () => _close(null), child: const Text('Cancel')),
    ],
  );
}
