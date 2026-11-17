import 'dart:convert';

import 'package:kartka_desktop/kartka_desktop.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// `/agent` tells the app it runs in the headless agent instance, which
/// must never file board tickets from its checks.
void main() {
  test('the agent wrapper says so; any other says no', () async {
    final agent = await Harness.start(agent: true);
    addTearDown(agent.close);
    final plain = await Harness.start();
    addTearDown(plain.close);
    final yes = await agent.call('GET', agentPath);
    expect(yes.status, 200);
    expect(jsonDecode(utf8.decode(yes.body)), {'agent': true});
    final no = await plain.call('GET', agentPath);
    expect(jsonDecode(utf8.decode(no.body)), {'agent': false});
    expect((await agent.call('GET', agentPath, api: false)).status, 403);
  });
}
