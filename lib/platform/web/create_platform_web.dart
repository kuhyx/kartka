// coverage:ignore-file
// Thin wiring of browser APIs; the pieces it assembles (ProxyKartkaHttp,
// WrapperBrowser, the wrapper stores, IdbKeyValueStore,
// WrapperOAuthRedirect) are unit-tested on the VM.
import 'package:http/http.dart' as http;
import 'package:idb_shim/idb_browser.dart';
import 'package:kartka/platform/caching_key_value_store.dart';
import 'package:kartka/platform/http_kartka.dart';
import 'package:kartka/platform/oauth_impls.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/platform/plugin_file_picker.dart';
import 'package:kartka/platform/web/idb_key_value_store.dart';
import 'package:kartka/platform/web/web_directory_picker.dart';
import 'package:kartka/platform/wrapper_browser.dart';
import 'package:kartka/platform/wrapper_stores.dart';
import 'package:web/web.dart' as web;

/// Builds the web (desktop Chrome app) platform, served by the wrapper.
Future<KartkaPlatform> createPlatform() async {
  final here = Uri.base;
  final base = Uri(scheme: here.scheme, host: here.host, port: here.port);
  final client = http.Client();
  return KartkaPlatform(
    http: ProxyKartkaHttp(client, base),
    blobs: WrapperBlobStore(client, base),
    // Same /files root: the log lands as a file on the PC, no export step.
    diagnostics: WrapperBlobStore(client, base),
    kv: await IdbKeyValueStore.open(idbFactoryBrowser),
    // One backend read per key per launch (the AniList token was re-fetched
    // on every progress push); the app's own writes keep it current.
    secrets: CachingKeyValueStore(WrapperKeyValueStore(client, base)),
    filePicker: PluginFilePicker(pickDirectory: pickWebDirectory),
    oauth: WrapperOAuthRedirect(
      client: client,
      base: base,
      open: (url) => web.window.open(url.toString(), '_blank'),
    ),
    browser: WrapperBrowser(client, base),
    // Covers land under files/cache/ on the PC (CoverCache.prefix).
    cache: WrapperBlobStore(client, base),
  );
}
