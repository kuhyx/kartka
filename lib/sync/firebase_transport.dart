/// [RtdbTransport] over Firebase RTDB's REST API.
///
/// Writes go through crdt_sync's own `FirebaseRestClient.patchValues`
/// (DOCS-contracts §12). Reads cannot: its `getFileText` only accepts string
/// leaves and `getStringMap` drops non-strings, while §4 nodes are JSON
/// objects. So reads are a plain authenticated GET through [KartkaHttp],
/// with the token from the same client's auth.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/sync/off_ui_json.dart';
import 'package:kartka/sync/rtdb_transport.dart';

/// The pre-e2e RTDB root. Since e2e it is only read (the one-time copy);
/// the data lives under `kE2eLayout.prefix` (lib/sync/e2e/).
const String kKartkaRoot = 'kartka';

/// Minimal write surface of `FirebaseRestClient`, so tests can fake it.
abstract interface class RtdbWriter {
  /// Mints the ID token for a request.
  Future<String> idToken();

  /// Multi-path update of the map at [path].
  Future<void> patchValues(String path, Map<String, Object?> values);
}

/// Adapts a signed-in [FirebaseRestClient] to [RtdbWriter].
class FirebaseRestWriter implements RtdbWriter {
  /// Wraps [client].
  new(this.client);

  /// The signed-in client (owned by the caller).
  final FirebaseRestClient client;

  @override
  Future<String> idToken() => client.auth.idToken();

  @override
  Future<void> patchValues(String path, Map<String, Object?> values) =>
      client.patchValues(path, values);
}

/// Reads and writes `/<root>` on the RTDB at `databaseUrl`.
class FirebaseTransport implements RtdbTransport {
  /// Creates a transport; [databaseUrl] is the regional RTDB host.
  ///
  /// [namespace] (default: the `SYNC_NAMESPACE` dart-define, as in
  /// crdt_sync) is empty for production or `sandbox/<slot>`; reads then live
  /// under `/<namespace>/`, matching the writes crdt_sync's client prefixes.
  /// Anything else throws (fail closed).
  new({
    required this.writer,
    required this.http,
    required String databaseUrl,
    required this.root,
    String? namespace,
  }) : _namespace = checkSyncNamespace(namespace ?? syncNamespace),
       _base = Uri.parse(
         databaseUrl.endsWith('/')
             ? databaseUrl.substring(0, databaseUrl.length - 1)
             : databaseUrl,
       );

  /// Token source and writer.
  final RtdbWriter writer;

  /// HTTP for reads.
  final KartkaHttp http;

  /// The RTDB node every path is relative to.
  final String root;

  final Uri _base;
  final String _namespace;

  @override
  Future<Object?> get(String path) async {
    final segments = [
      ..._namespace.split('/').where((s) => s.isNotEmpty),
      ...root.split('/'),
      ...path.split('/').where((s) => s.isNotEmpty),
    ];
    final last = '${segments.removeLast()}.json';
    final url = _base.replace(
      pathSegments: [..._base.pathSegments, ...segments, last],
      queryParameters: {'auth': await writer.idToken()},
    );
    final KartkaResponse res;
    try {
      res = await http.get(url);
    } on Exception catch (e) {
      // A ClientException prints `uri=` with the `?auth=` ID token. As a
      // sync error the engine shows it and keeps going; escaping, it would
      // fail the engine's queue and land in logcat as an unhandled error.
      throw FirebaseSyncError(
        'network error reading $path: ${redactUrlQueries('$e')}',
      );
    }
    if (!res.ok) {
      // Never "no data" on failure: a rejected read must not look like an
      // empty database, or the engine would happily re-push everything.
      throw FirebaseSyncError('reading $path failed: HTTP ${res.statusCode}');
    }
    // Full pulls and the source-health tree can be MBs: decoded off-UI.
    return await decodeJsonOffUi(res.body);
  }

  @override
  Future<void> patch(Map<String, Object?> updates) =>
      writer.patchValues(root, updates);
}
