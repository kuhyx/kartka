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
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/file_picker.dart';
import 'package:kartka/platform/memory/memory_platform.dart';

import 'fakes.dart';
import 'fixture_builder.dart';

LibraryRepositories _library(MemoryKeyValueStore kv) =>
    LibraryRepositories(kv, decorators: () => const []);

KartkaEnv _env(List<Object> services, {FakeFilePicker? picker}) =>
    KartkaEnv(memoryPlatform(filePicker: picker))
      ..registry = KartkaRegistry([
        KartkaFeature(id: 'library', services: services),
      ]);

class _Source implements MangaSource {
  new(String id)
    : ref = SourceRef(
        id: id,
        name: id,
        lang: 'en',
        origin: SourceOrigin.native,
      );

  @override
  final SourceRef ref;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test(
    'available sources come from every SourceProvider, else unknown',
    () async {
      expect(await availableSourceIds(_env([])), isNull);
      final env = _env([
        StaticSourceProvider([_Source('mangadex')]),
        StaticSourceProvider([_Source('suwayomi:1')]),
      ]);
      expect(await availableSourceIds(env), {'mangadex', 'suwayomi:1'});
    },
  );

  test('resolveRepositories reads the library accessor', () {
    final repos = _library(MemoryKeyValueStore());
    final r = resolveRepositories(_env([repos]));
    expect(r.library, same(repos.library));
    expect(r.progress, same(repos.progress));
  });

  test('resolveRepositories fails clearly without a library', () {
    expect(() => resolveRepositories(_env([])), throwsStateError);
  });

  test('bindings go to a registered sink and are skipped without one', () {
    final repos = _library(MemoryKeyValueStore());
    expect(buildImporter(_env([repos]), resolveRepositories).bindings, isNull);
    final sink = FakeBindings();
    expect(
      buildImporter(_env([repos, sink]), resolveRepositories).bindings,
      same(sink),
    );
  });

  test('import through the real local repositories is idempotent', () async {
    final importer = buildImporter(
      _env([_library(MemoryKeyValueStore()), FakeBindings()]),
      resolveRepositories,
    );
    final plan = const BackupPlanner(SourceMapper())
        .plan(decodeTachibk(buildSyntheticTachibk()));
    final first = await importer.apply(plan);
    expect(first.entries, 6);
    expect(first.readMarks, 6);
    expect(first.progress, 3);
    expect(first.bindings, 3);
    final again = await importer.apply(plan);
    expect(again.changedNothing, isTrue);
  });

  testWidgets('More tile opens the import screen', (tester) async {
    final feature = backupImportFeatureWith(
      _env(
        [
          _library(MemoryKeyValueStore()),
          StaticSourceProvider([_Source('mangadex')]),
        ],
        picker: FakeFilePicker(
          files: [
            PickedFile(
              name: 'sy.tachibk',
              read: () async => buildSyntheticTachibk(),
            ),
          ],
        ),
      ),
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

    // The default planner runs in an isolate, so give it real time.
    await tester.tap(find.text('Choose backup file'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Source unavailable'), findsOneWidget);
    expect(find.text('AllManga (4709139914729853090)'), findsOneWidget);
  });

  test('the registry entry point wires the real resolver', () {
    final feature = backupImportFeature(
      _env([_library(MemoryKeyValueStore())]),
    );
    expect(feature.routes, hasLength(1));
  });
}
