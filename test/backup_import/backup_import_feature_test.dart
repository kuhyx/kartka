import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/backup_import/backup_import_feature.dart';
import 'package:kartka/backup_import/import_screen.dart';
import 'package:kartka/backup_import/repositories_seam.dart';
import 'package:kartka/backup_import/tracker_binding_sink.dart';
import 'package:kartka/platform/platform.dart';

import 'fakes.dart';

class _Unused implements KartkaHttp, BlobStore, OAuthRedirect {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Kv implements KeyValueStore {
  @override
  Future<String?> get(String key) async => null;
  @override
  Future<void> set(String key, String value) async {}
  @override
  Future<void> remove(String key) async {}
  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {};
}

class _Picker implements FilePicker {
  @override
  Future<List<PickedFile>> pickFiles({
    List<String> extensions = const [],
    bool multiple = false,
  }) async => [PickedFile(name: 'x.tachibk', read: () async => Uint8List(0))];

  @override
  Future<List<PickedFile>> pickDirectory() async => [];
}

KartkaEnv _env(List<Object> services) {
  final unused = _Unused();
  final env = KartkaEnv(
    KartkaPlatform(
      http: unused,
      blobs: unused,
      kv: _Kv(),
      secrets: _Kv(),
      filePicker: _Picker(),
      oauth: unused,
    ),
  );
  env.registry = KartkaRegistry([
    KartkaFeature(id: 'library', services: services),
  ]);
  return env;
}

List<Object> _repos() => [FakeLibrary(), FakeCategories(), FakeProgress()];

void main() {
  test('resolveRepositories reads the registry services', () {
    final r = resolveRepositories(_env(_repos()));
    expect(r.library, isA<FakeLibrary>());
    expect(r.categories, isA<FakeCategories>());
    expect(r.progress, isA<FakeProgress>());
  });

  test('resolveRepositories fails clearly without a library', () {
    expect(() => resolveRepositories(_env([])), throwsStateError);
  });

  test('the importer uses a registered binding sink, else the kv store', () {
    final env = _env(_repos());
    expect(
      buildImporter(env, resolveRepositories).bindings,
      isA<KvTrackerBindingStore>(),
    );
    final sink = FakeBindings();
    final env2 = _env([..._repos(), sink]);
    expect(buildImporter(env2, resolveRepositories).bindings, same(sink));
  });

  testWidgets('More tile opens the import screen', (tester) async {
    final feature = backupImportFeatureWith(
      _env(_repos()),
      resolveRepositories,
    );
    expect(feature.id, 'backup_import');
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) =>
              Scaffold(body: Builder(builder: feature.settingsTiles.single)),
        ),
        ...feature.routes.cast<GoRoute>(),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Import SY backup'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportScreen), findsOneWidget);
    expect(router.state.uri.toString(), importSyBackupRoute);
  });

  test('the registry entry point wires the real resolver', () {
    final feature = backupImportFeature(_env(_repos()));
    expect(feature.routes, hasLength(1));
  });
}
