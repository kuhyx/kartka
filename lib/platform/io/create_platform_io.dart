// coverage:ignore-file
// Thin wiring of plugins that need a device (path_provider, the Keystore,
// app links); every piece it assembles is unit-tested on its own.
// phone-slot: not-shared-storage (getExternalStorageDirectory is per-package).
import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:kartka/core/diagnostics/startup_marks.dart';
import 'package:kartka/platform/caching_key_value_store.dart';
import 'package:kartka/platform/coalescing_saver.dart';
import 'package:kartka/platform/cookie_http.dart';
import 'package:kartka/platform/http_kartka.dart';
import 'package:kartka/platform/io/channel_extension_runtime.dart';
import 'package:kartka/platform/io/directory_files.dart';
import 'package:kartka/platform/io/file_stores.dart';
import 'package:kartka/platform/io/secure_key_value_store.dart';
import 'package:kartka/platform/io/webview_browser.dart';
import 'package:kartka/platform/oauth_impls.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/platform/plugin_file_picker.dart';
import 'package:kartka/platform/split_key_value_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Builds the Android platform.
Future<KartkaPlatform> createPlatform() async {
  // The kv read (~20 MB of shards, the library's first paint waits on it)
  // starts as soon as its directory is known, beside the other directory
  // calls, the error queue, the registry and the first frame
  // (library.load a133bbb8).
  final support = await getApplicationSupportDirectory();
  // Sharded since 2026-10-29; the first launch migrates the old kv.json.
  final fastKv = FileKeyValueStore(
    Directory(p.join(support.path, 'kv')),
    legacy: File(p.join(support.path, 'kv.json')),
  )..warm();
  // Sync state and chapter lists, read once the library's keys are in.
  // Its own marks: the launch line times the read the library waits on.
  final deferredKv = FileKeyValueStore(
    Directory(p.join(support.path, 'kv-deferred')),
    marks: StartupMarks(),
  );
  final kv = SplitKeyValueStore(
    fastKv,
    deferredKv,
    deferredPrefixes: kvDeferredPrefixes,
    flushFast: fastKv.flush,
    flushDeferred: deferredKv.flush,
  );
  // Moves the keys written before the split, well after the first paint;
  // a failure is retried on the next launch (the move is copy-first).
  Timer(const Duration(seconds: 10), () => kv.migrate().ignore());
  final (docs, cacheDir, external) = await (
    getApplicationDocumentsDirectory(),
    getApplicationCacheDirectory(),
    // getExternalFilesDir(null): adb can pull it from a release build.
    getExternalStorageDirectory(),
  ).wait;
  // Held by the binding for the app's lifetime: pause/detach writes kv/.
  flushOnBackground(kv.flush);
  final hosts = WebViewHosts(kv);
  return KartkaPlatform(
    http: CookieKartkaHttp(
      DirectKartkaHttp(http.Client()),
      hosts,
      cookieFor: webViewCookieFor,
    ),
    blobs: FileBlobStore(Directory(p.join(docs.path, 'blobs'))),
    diagnostics: FileBlobStore(external ?? support),
    kv: kv,
    // One Keystore read per key per launch; the app's writes keep it current.
    secrets: CachingKeyValueStore(
      SecureKeyValueStore(const FlutterSecureStorage()),
    ),
    filePicker: PluginFilePicker(
      pickDirectory: () async => await listDirectoryFiles(
        // Deprecated for pickDirectory's content:// Uri, which dart:io
        // cannot list; the path still works until a SAF reader exists.
        // ignore: deprecated_member_use
        await fp.FilePicker.getDirectoryPath(),
      ),
    ),
    oauth: DeepLinkOAuthRedirect(
      launch: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
      links: AppLinks().uriLinkStream,
    ),
    browser: WebViewBrowser(hosts),
    extensions: const ChannelExtensionRuntime(),
    // Covers: the OS may clear this dir, and then they are fetched again.
    cache: FileBlobStore(Directory(p.join(cacheDir.path, 'blobs'))),
  );
}
