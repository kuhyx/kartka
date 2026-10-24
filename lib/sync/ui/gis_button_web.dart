// coverage:ignore-file
// Web-only plugin glue: google_sign_in_web cannot load on the VM test runner.
// The routing and the dialog around it are covered in google_route_test.dart.
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web_only;

// The web plugin's init() throws StateError on a second call, so the first
// call's future is kept and shared.
Future<void>? _initialized;

/// Initialises GIS for [clientId] once per page load.
///
/// No nonce, deliberately: Firebase requires the raw nonce back whenever the
/// ID token carries one, and crdt_sync's `signInWithIdp` sends none.
Future<void> gisInitialize(String clientId) =>
    _initialized ??= GoogleSignIn.instance.initialize(clientId: clientId);

/// The GIS-rendered "Sign in with Google" button.
Widget gisButton() => web_only.renderButton(
  configuration: web_only.GSIButtonConfiguration(
    theme: web_only.GSIButtonTheme.filledBlack,
    size: web_only.GSIButtonSize.large,
    shape: web_only.GSIButtonShape.pill,
  ),
);

/// ID tokens from button sign-ins; plugin failures arrive as stream errors.
Stream<String> gisIdTokens() => GoogleSignIn.instance.authenticationEvents
    .map(
      (event) => switch (event) {
        GoogleSignInAuthenticationEventSignIn(:final user) =>
          user.authentication.idToken,
        GoogleSignInAuthenticationEventSignOut() => null,
      },
    )
    .where((token) => token != null)
    .cast<String>();
