import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/backup_import/backup_import_feature.dart';
import 'package:kartka/backup_import/backup_planner.dart';
import 'package:kartka/backup_import/import_screen.dart';
import 'package:kartka/backup_import/repositories_seam.dart';
import 'package:kartka/backup_import/source_mapper.dart';
import 'package:kartka/backup_import/tachibk_decoder.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/platform.dart';

import '../library/support/memory_kv.dart';
import 'fakes.dart';
import 'fixture_builder.dart';

class _Http implements KartkaHttp {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Blobs implements BlobStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _OAuth implements OAuthRedirect {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Picker implements FilePicker {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

LibraryRepositories _library(MemoryKv kv) =>
    LibraryRepositories(kv, decorators: () => const []);

KartkaEnv _env(List<Object> services, {MemoryKv? kv}) {
  return KartkaEnv(
      KartkaPlatform(
        http: _Http(),
        blobs: _Blobs(),
        kv: kv ?? MemoryKv(),
        secrets: MemoryKv(),
        filePicker: _Picker(),
        oauth: _OAuth(),
      ),
    )
    ..registry = KartkaRegistry([
      KartkaFeature(id: 'library', services: services),
    ]);
}

void main() {
  test('resolveRepositories reads the library accessor', () {
    final repos = _library(MemoryKv());
    final r = resolveRepositories(_env([repos]));
    expect(r.library, same(repos.library));
    expect(r.progress, same(repos.progress));
  });

  test('resolveRepositories fails clearly without a library', () {
    expect(() => resolveRepositories(_env([])), throwsStateError);
  });

  test('bindings go to a registered sink and are skipped without one', () {
    final repos = _library(MemoryKv());
    expect(buildImporter(_env([repos]), resolveRepositories).bindings, isNull);
    final sink = FakeBindings();
    expect(
      buildImporter(_env([repos, sink]), resolveRepositories).bindings,
      same(sink),
    );
  });

  test('import through the real local repositories is idempotent', () async {
    final importer = buildImporter(
      _env([_library(MemoryKv()), FakeBindings()]),
      resolveRepositories,
    );
    final plan = const BackupPlanner(SourceMapper())
        .plan(decodeTachibk(buildSyntheticTachibk()));
    final first = await importer.apply(plan);
    expect(first.entries, 6);
    expect(first.readMarks, 6);
    expect(first.progress, 3);
    expect(first.bindings, 2);
    final again = await importer.apply(plan);
    expect(again.changedNothing, isTrue);
  });

  testWidgets('More tile opens the import screen', (tester) async {
    final feature = backupImportFeatureWith(
      _env([_library(MemoryKv())]),
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
    final feature = backupImportFeature(_env([_library(MemoryKv())]));
    expect(feature.routes, hasLength(1));
  });
}
