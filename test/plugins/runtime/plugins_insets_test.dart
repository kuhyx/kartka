import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/plugins/runtime/plugins_screen.dart';

import 'support.dart';

void main() {
  const repo = 'https://repo.test/index.json';

  testWidgets('every row keeps the screen gutter', (t) async {
    final kv = MemoryKeyValueStore();
    await PluginStore(kv).setRepos([repo]);
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
    await t.pumpAndSettle();
    for (final row in [
      find.text('Repositories'),
      find.byType(TextField),
      find.text(repo),
      find.text('Available'),
      find.text('Demo Site'),
      find.text('Installed'),
    ]) {
      expect(
        t.getTopLeft(row).dx,
        greaterThanOrEqualTo(AppSpacing.md),
        reason: '$row',
      );
    }
  });
}
