import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_registrar.dart';
import 'package:kartka/plugins/runtime/plugin_repo_adapter.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/plugins/runtime/plugins_feature.dart';
import 'package:kartka/plugins/runtime/plugins_screen.dart';
import 'package:kartka/plugins/runtime/plugins_sections.dart';

import 'support.dart';

class _Adapter implements PluginRepoAdapter {
  int parsed = 0;
  @override
  bool accepts(Object? indexJson) =>
      indexJson is Map && indexJson['foreign'] == true;
  @override
  List<PluginIndexEntry> parse(Object? json, Uri indexUrl) {
    parsed++;
    return [];
  }

  @override
  Future<String> buildSource(PluginIndexEntry e, String js) async => js;
}

void main() {
  const repo = 'https://repo.test/index.json';
  late FakeHttp http;
  late MemoryKeyValueStore kv;
  late PluginManager manager;

  setUp(() {
    http = FakeHttp();
    kv = MemoryKeyValueStore();
    manager = PluginManager(http: http.client, store: PluginStore(kv));
  });

  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: PluginsScreen(manager: manager),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> addRepo(WidgetTester t, String url) async {
    await t.enterText(find.byType(TextField), url);
    await t.tap(find.byTooltip('Add repository'));
    await t.pumpAndSettle();
  }

  testWidgets('submitting from the keyboard adds the repo', (t) async {
    await open(t);
    await t.enterText(find.byType(TextField), repo);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text(repo), findsOneWidget);
  });

  testWidgets('the add row shows a spinner while busy', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddRepoRow(
            controller: TextEditingController(),
            busy: true,
            onAdd: () {},
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Add repository'), findsNothing);
  });

  testWidgets('empty state explains what to do', (t) async {
    await open(t);
    expect(find.text('Add a repository URL to find plugins.'), findsOneWidget);
    expect(find.text('No plugins installed.'), findsOneWidget);
  });

  testWidgets('add repo, install, see it installed, uninstall', (t) async {
    await open(t);
    await addRepo(t, repo);
    expect(find.text(repo), findsOneWidget);
    expect(find.text('Demo Site'), findsOneWidget);
    expect(find.text('Install'), findsNWidgets(2));

    await t.tap(find.text('Install').first);
    await t.pumpAndSettle();
    expect(find.text('plugin:demo · 1.0.0 · $repo'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await t.tap(find.byTooltip('Uninstall Demo Site'));
    await t.pumpAndSettle();
    expect(find.text('Uninstall Demo Site?'), findsOneWidget);
    await t.tap(find.text('Uninstall'));
    await t.pumpAndSettle();
    expect(find.text('No plugins installed.'), findsOneWidget);
  });

  testWidgets('cancelling the uninstall dialog keeps the plugin', (t) async {
    await open(t);
    await addRepo(t, repo);
    await t.tap(find.text('Install').first);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Uninstall Demo Site'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('No plugins installed.'), findsNothing);
  });

  testWidgets('a newer version shows Update', (t) async {
    await PluginStore(kv).setRepos([repo]);
    await PluginStore(kv).put(
      InstalledPlugin(
        manifest: (await manager.available()).plugins.first.entry.manifest,
        source: 'x',
        origin: repo,
      ),
    );
    http.overrides['https://repo.test/index.json'] = (
      status: 200,
      body: fixture('index.json').replaceFirst('"1.0.0"', '"2.0.0"'),
    );
    await open(t);
    expect(find.text('Update'), findsOneWidget);
    await t.tap(find.text('Update'));
    await t.pumpAndSettle();
    expect(find.text('Update'), findsNothing);
  });

  testWidgets('a failing repo shows its error and can be removed', (t) async {
    await PluginStore(kv).setRepos(['https://repo.test/gone.json']);
    await open(t);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await t.tap(find.byTooltip('Remove repository'));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('an empty repo says so', (t) async {
    http.overrides['https://repo.test/empty.json'] = (
      status: 200,
      body: '{"plugins":[]}',
    );
    await PluginStore(kv).setRepos(['https://repo.test/empty.json']);
    await open(t);
    expect(find.text('These repositories offer no plugins.'), findsOneWidget);
  });

  testWidgets('install errors name the plugin in a toast', (t) async {
    await open(t);
    await addRepo(t, repo);
    http.overrides['https://repo.test/demo.js'] = (status: 200, body: 'evil()');
    await t.tap(find.text('Install').first);
    await t.pumpAndSettle();
    expect(find.textContaining('Plugin "demo"'), findsOneWidget);
    expect(find.textContaining('sha256 mismatch'), findsOneWidget);
  });

  testWidgets('an invalid repo url is rejected and kept in the field', (
    t,
  ) async {
    await open(t);
    await addRepo(t, 'ftp://nope');
    expect(find.textContaining('repo URL must be http'), findsOneWidget);
    expect(find.text('ftp://nope'), findsOneWidget);
  });

  testWidgets('feature wires route, settings tile and services', (t) async {
    final adapter = _Adapter();
    final registry = KartkaRegistry.build(
      memoryPlatform(http: http.client, kv: kv),
      [
        (env) => pluginsFeature(env, engineFactory: QuickJsEngine.new),
        (env) => KartkaFeature(id: 'x', services: [adapter]),
      ],
    );
    final feature = registry.features.first;
    expect(feature.id, 'plugins');
    expect(registry.all<SourceProvider>(), hasLength(1));
    final manager = registry.maybe<PluginRegistrar>()! as PluginManager;
    expect(
      await t.runAsync(
        () => registry.all<SourceProvider>().single.watch().first,
      ),
      isEmpty,
    );
    http.overrides['https://repo.test/foreign.json'] = (
      status: 200,
      body: '{"foreign": true}',
    );
    await t.runAsync(() => manager.addRepo('https://repo.test/foreign.json'));
    expect(adapter.parsed, 1);

    await t.runAsync(() async {
      await manager.installLocal(
        const PluginManifest(
          id: 'demo',
          name: 'Demo',
          version: '1',
          lang: 'en',
          baseUrl: 'https://demo.test',
        ),
        fixture('demo.js'),
        origin: 'test',
      );
      final sources = await registry.all<SourceProvider>().single.watch().first;
      expect((await sources.single.popular(1)).items, hasLength(2));
    });

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => Scaffold(body: feature.settingsTiles.single(c)),
        ),
        ...feature.routes,
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.tap(find.text('Plugins'));
    await t.pumpAndSettle();
    expect(find.byType(PluginsScreen), findsOneWidget);
  });
}
