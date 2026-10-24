import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sync/google_client.dart';
import 'package:kartka/sync/ui/gis_button.dart' as gis;
import 'package:kartka/sync/ui/google_route.dart';

void main() {
  test('the Web client id is compiled in, so the button is offered', () {
    // Emptying this const silently disables Google sign-in everywhere,
    // which is the state this whole feature exists to end.
    expect(kKartkaGoogleClientId, endsWith('.apps.googleusercontent.com'));
  });

  test('Google sign-in is offered when the client id is configured', () {
    expect(
      googleRouteFor(
        isWeb: false,
        pluginSupported: true,
        clientId: kKartkaGoogleClientId,
      ),
      GoogleRoute.plugin,
    );
    expect(
      googleRouteFor(
        isWeb: true,
        pluginSupported: false,
        clientId: kKartkaGoogleClientId,
      ),
      GoogleRoute.webButton,
    );
  });

  test('no client id or no flow means no button', () {
    expect(
      googleRouteFor(isWeb: true, pluginSupported: true, clientId: ''),
      GoogleRoute.none,
    );
    expect(
      googleRouteFor(isWeb: false, pluginSupported: false, clientId: 'x'),
      GoogleRoute.none,
    );
  });

  test('the VM stub refuses rather than pretending to sign in', () {
    expect(() => gis.gisInitialize('x'), throwsUnsupportedError);
    expect(gis.gisButton, throwsUnsupportedError);
    expect(gis.gisIdTokens, throwsUnsupportedError);
  });

  /// Pumps a host and returns its context, so the fetch can be started
  /// without overlapping a pending pumpWidget.
  Future<BuildContext> host(WidgetTester t) async {
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
    return context;
  }

  testWidgets('plugin route asks the plugin; none asks nobody', (t) async {
    final sources = GoogleTokenSources(plugin: (_) async => 'tok');
    final c = await host(t);
    final plugin = fetchGoogleIdToken(c, GoogleRoute.plugin, sources: sources);
    expect(await plugin, 'tok');
    final none = fetchGoogleIdToken(c, GoogleRoute.none, sources: sources);
    expect(await none, isNull);
    // The default reaches crdt_sync_flutter, which refuses an empty id
    // before touching the platform channel.
    expect(await const GoogleTokenSources().plugin(''), isNull);
  });

  GoogleTokenSources webSources(
    StreamController<String> tokens,
    List<String> inits,
  ) => GoogleTokenSources(
    gisInit: (id) async => inits.add(id),
    gisButton: () => const Text('GIS button'),
    gisTokens: () => tokens.stream,
  );

  testWidgets('web route: the GIS button token closes the dialog', (t) async {
    final tokens = StreamController<String>.broadcast();
    final inits = <String>[];
    final c = await host(t);
    final result = fetchGoogleIdToken(
      c,
      GoogleRoute.webButton,
      sources: webSources(tokens, inits),
    );
    await t.pumpAndSettle();
    expect(inits, [kKartkaGoogleClientId]);
    expect(find.text('GIS button'), findsOneWidget);
    tokens.add('id-token');
    await t.pumpAndSettle();
    expect(await result, 'id-token');
    expect(find.text('GIS button'), findsNothing);
  });

  testWidgets('web route: Cancel and stream errors yield null', (t) async {
    final tokens = StreamController<String>.broadcast();
    final sources = webSources(tokens, []);
    final c = await host(t);
    final cancelled = fetchGoogleIdToken(
      c,
      GoogleRoute.webButton,
      sources: sources,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(await cancelled, isNull);

    final failed = fetchGoogleIdToken(
      c,
      GoogleRoute.webButton,
      sources: sources,
    );
    await t.pumpAndSettle();
    tokens.addError(StateError('popup closed'));
    await t.pumpAndSettle();
    expect(await failed, isNull);
  });
}
