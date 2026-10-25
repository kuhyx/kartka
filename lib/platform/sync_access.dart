/// How crdt_sync_flutter reaches the sync account on this build
/// (DOCS-contracts-runtime §17).
library;

import 'package:crdt_sync/crdt_sync.dart'
    show FirebaseAccount, FirebaseRestClient;
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' as crdt;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:kartka/platform/wrapper_protocol.dart';

/// The sync app plus the HTTP client crdt_sync_flutter should use.
///
/// Web (desktop): the app carries the wrapper's seeded-session route, so a
/// signed-out install adopts a session the wrapper serves (only the headless
/// agent instance's wrapper has one; elsewhere the route answers 404 and the
/// normal sign-in screen shows). The client adds `x-kartka: 1` to wrapper
/// requests, as every wrapper API route requires. Android: neither.
class SyncAccess {
  /// The access for this build; [base] defaults to `Uri.base` and [inner]
  /// (the wrapped client) to a fresh `http.Client`.
  factory of(
    crdt.SyncApp app, {
    bool isWeb = kIsWeb,
    Uri? base,
    http.Client? inner,
  }) {
    if (!isWeb) return SyncAccess._(app, null, null);
    final here = base ?? Uri.base;
    final origin = Uri(scheme: here.scheme, host: here.host, port: here.port);
    return SyncAccess._(
      crdt.SyncApp(
        project: app.project,
        expectedUid: app.expectedUid,
        routes: const crdt.WrapperRoutes(
          credentialsPath: KartkaWrapper.syncCredentialsPath,
        ),
      ),
      WrapperApiClient(inner ?? http.Client(), origin),
      origin,
    );
  }

  new _(this.app, this.client, this._origin);

  /// The sync app, with the wrapper route on the web build.
  final crdt.SyncApp app;

  /// Client for every crdt_sync_flutter request; null means its default.
  final http.Client? client;

  // The wrapper origin the seeded route resolves against. openSync has no
  // such parameter and uses `Uri.base`, which on the web build is the same.
  final Uri? _origin;

  /// The account screen's loader: the stored account, else (web) the
  /// seeded session.
  Future<FirebaseAccount?> loadAccount() =>
      crdt.loadAccount(routes: app.routes, base: _origin, httpClient: client);

  /// A signed-in client, adopting a seeded session first if there is one.
  Future<FirebaseRestClient?> openSync() =>
      crdt.openSync(app, httpClient: client);
}

/// Adds `x-kartka: 1` to requests for [origin] only.
///
/// The same client carries Firebase's token and RTDB calls; a custom header
/// on those would force a CORS preflight Google does not grant.
class WrapperApiClient extends http.BaseClient {
  /// Wraps [_inner] for the wrapper at [origin].
  new(this._inner, this.origin);

  final http.Client _inner;

  /// The wrapper's scheme, host and port.
  final Uri origin;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final url = request.url;
    if (url.scheme == origin.scheme &&
        url.host == origin.host &&
        url.port == origin.port) {
      request.headers[KartkaWrapper.apiHeader] = '1';
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
