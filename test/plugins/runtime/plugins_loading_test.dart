import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/plugins/runtime/plugins_screen.dart';

import 'support.dart';

/// A store whose reads wait for [open], like a cold kv on a slow phone.
class _GatedKv implements KeyValueStore {
  final _inner = MemoryKeyValueStore();
  final open = Completer<void>();

  @override
  Future<String?> get(String key) async {
    await open.future;
    return await _inner.get(key);
  }

  @override
  Future<void> set(String key, String value) => _inner.set(key, value);

  @override
  Future<void> remove(String key) => _inner.remove(key);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async {
    await open.future;
    return await _inner.entries(prefix: prefix);
  }
}

void main() {
  testWidgets('shows a loading state, not the empty state, before data', (
    t,
  ) async {
    final kv = _GatedKv();
    final manager = PluginManager(
      http: FakeHttp().client,
      store: PluginStore(kv),
    );
    await t.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: PluginsScreen(manager: manager),
      ),
    );
    await t.pump();
    const noRepos = 'Add a repository URL to find plugins.';
    const noneInstalled = 'No plugins installed.';
    expect(find.bySemanticsLabel(noRepos), findsNothing);
    expect(find.bySemanticsLabel(noneInstalled), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    kv.open.complete();
    await t.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel(noRepos), findsOneWidget);
    expect(find.bySemanticsLabel(noneInstalled), findsOneWidget);
  });
}
