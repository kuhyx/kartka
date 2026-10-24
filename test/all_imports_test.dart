// Loads every lib/ file that can run on the VM, so `flutter test --coverage`
// reports each one (an unloaded file is silently missing from lcov, which
// makes a 100 % figure hollow). The test below keeps this list complete.
// ignore_for_file: unused_import
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/app.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/app/scope.dart';
import 'package:kartka/app/shell.dart';
import 'package:kartka/core/models/category.dart';
import 'package:kartka/core/models/chapter_info.dart';
import 'package:kartka/core/models/download_state.dart';
import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/models/library_entry.dart';
import 'package:kartka/core/models/manga.dart';
import 'package:kartka/core/models/manga_key.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/models/page_ref.dart';
import 'package:kartka/core/models/reading_progress.dart';
import 'package:kartka/core/models/search_page.dart';
import 'package:kartka/core/models/source_ref.dart';
import 'package:kartka/core/repositories/category_repository.dart';
import 'package:kartka/core/repositories/download_repository.dart';
import 'package:kartka/core/repositories/library_repository.dart';
import 'package:kartka/core/repositories/progress_repository.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/platform/create_platform.dart';
import 'package:kartka/platform/file_picker.dart';
import 'package:kartka/platform/fullscreen.dart';
import 'package:kartka/platform/fullscreen_stub.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/http_kartka.dart';
import 'package:kartka/platform/image_headers.dart';
import 'package:kartka/platform/io/directory_files.dart';
import 'package:kartka/platform/io/file_stores.dart';
import 'package:kartka/platform/io/secure_key_value_store.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/platform/oauth_impls.dart';
import 'package:kartka/platform/oauth_redirect.dart';
import 'package:kartka/platform/page_image.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/platform/plugin_file_picker.dart';
import 'package:kartka/platform/web/idb_key_value_store.dart';
import 'package:kartka/platform/wrapper_protocol.dart';
import 'package:kartka/platform/wrapper_stores.dart';
import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/engine_default.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/engine_unsupported.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/host_dispatch.dart';
import 'package:kartka/plugins/runtime/html_parser_bundle.g.dart';
import 'package:kartka/plugins/runtime/kartka_host_services.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_mapping.dart';
import 'package:kartka/plugins/runtime/plugin_registrar.dart';
import 'package:kartka/plugins/runtime/plugin_repo_adapter.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';
import 'package:kartka/plugins/runtime/plugin_source.dart';
import 'package:kartka/plugins/runtime/plugin_source_provider.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/plugins/runtime/plugins_feature.dart';
import 'package:kartka/plugins/runtime/plugins_screen.dart';
import 'package:kartka/plugins/runtime/plugins_sections.dart';
import 'package:kartka/plugins/runtime/polyfills.dart';
import 'package:kartka/plugins/runtime/prelude.dart';
import 'package:kartka/plugins/runtime/third_party_licenses.g.dart';
import 'package:kartka/plugins/runtime/worker_script.dart';

void main() {
  test('imports every lib/ file except coverage:ignore-file wiring', () {
    final imported = RegExp("^import 'package:kartka/(.+)';", multiLine: true)
        .allMatches(File('test/all_imports_test.dart').readAsStringSync())
        .map((m) => 'lib/${m.group(1)}')
        .toSet();
    final expected = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !_ignored(f))
        .map((f) => f.path.replaceAll(r'\', '/'))
        .toSet();
    expect(imported, expected);
  });
}

bool _ignored(File f) {
  final head = f.readAsStringSync();
  return head
      .substring(0, head.length.clamp(0, 400))
      .contains('coverage:ignore-file');
}
