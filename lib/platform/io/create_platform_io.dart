// coverage:ignore-file
// Thin wiring of plugins that need a device (path_provider, the Keystore,
// app links); every piece it assembles is unit-tested on its own.
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:kartka/platform/coalescing_saver.dart';
import 'package:kartka/platform/http_kartka.dart';
import 'package:kartka/platform/io/directory_files.dart';
import 'package:kartka/platform/io/file_stores.dart';
import 'package:kartka/platform/io/secure_key_value_store.dart';
import 'package:kartka/platform/oauth_impls.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/platform/plugin_file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Builds the Android platform.
Future<KartkaPlatform> createPlatform() async {
  final docs = await getApplicationDocumentsDirectory();
  final support = await getApplicationSupportDirectory();
  final kv = FileKeyValueStore(File(p.join(support.path, 'kv.json')));
  // Held by the binding for the app's lifetime: pause/detach writes kv.json.
  flushOnBackground(kv.flush);
  return KartkaPlatform(
    http: DirectKartkaHttp(http.Client()),
    blobs: FileBlobStore(Directory(p.join(docs.path, 'blobs'))),
    kv: kv,
    secrets: SecureKeyValueStore(const FlutterSecureStorage()),
    filePicker: PluginFilePicker(
      pickDirectory: () async =>
          await listDirectoryFiles(await fp.FilePicker.getDirectoryPath()),
    ),
    oauth: DeepLinkOAuthRedirect(
      launch: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
      links: AppLinks().uriLinkStream,
    ),
  );
}
