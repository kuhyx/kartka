@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';
import 'package:kartka/sync/ui/google_route.dart';

// Runs the real web glue (google_sign_in_web + the GIS script from
// accounts.google.com), which the VM suite's fake button cannot:
//   CHROME_EXECUTABLE=/usr/bin/chromium \
//     fvm flutter test --platform chrome test/sync/ui/gis_button_web_test.dart
// Pins that initialise + renderButton inside the dialog neither throw nor
// hang, and that Cancel still resolves the fetch.

/// Lets real browser work (script load, iframe) run between frames.
Future<void> _settleReal(WidgetTester t, {bool Function()? until}) async {
  for (var i = 0; i < 40 && !(until?.call() ?? false); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await t.pump();
  }
}

void main() {
  // The test host does not run the app's plugin registrant.
  setUpAll(() => GoogleSignInPlugin.registerWith(webPluginRegistrar));

  testWidgets('the real GIS button opens in the dialog and cancels', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    Object? failure;
    final token = fetchGoogleIdToken(context, GoogleRoute.webButton);
    unawaited(
      token.then((_) {}, onError: (Object e, StackTrace s) => failure = e),
    );
    final button = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate(
        (w) => '${w.runtimeType}'.contains('HtmlElementView'),
      ),
    );
    await _settleReal(t, until: () => button.evaluate().isNotEmpty);
    expect(failure, isNull);
    expect(button, findsWidgets);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(await token, isNull);
  });
}
