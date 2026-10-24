import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/host_dispatch.dart';

import 'support.dart';

void main() {
  late FakeServices services;
  late HostDispatcher d;
  setUp(() {
    services = FakeServices();
    d = HostDispatcher(services);
  });

  test('http.get and http.post return response JSON', () async {
    final g = await d.dispatch('http.get', [
      'https://demo.test/latest?page=1',
      {
        'headers': {'X': 1},
      },
    ]);
    expect((g! as Map)['status'], 200);
    final p = await d.dispatch('http.post', [
      'https://demo.test/latest?page=1',
      {'body': 5, 'headers': 'ignored'},
    ]);
    expect((p! as Map)['status'], 200);
    final miss = await d.dispatch('http.get', ['https://demo.test/x']);
    expect((miss! as Map)['status'], 404);
  });

  test('html.select, log and prefs', () async {
    final m = await d.dispatch('html.select', ['<b class="x">hi</b>', 'b.x']);
    expect((m! as List).single, containsPair('text', 'hi'));
    expect(await d.dispatch('log', ['msg']), isNull);
    expect(services.logs, ['msg']);
    expect(await d.dispatch('prefs.get', ['k']), isNull);
    await d.dispatch('prefs.set', ['k', 'v']);
    expect(await d.dispatch('prefs.get', ['k']), 'v');
  });

  test('rejects unknown ops and non-string arguments', () async {
    await expectLater(
      d.dispatch('fs.read', ['/etc/passwd']),
      throwsArgumentError,
    );
    await expectLater(d.dispatch('http.get', [42]), throwsArgumentError);
    await expectLater(d.dispatch('http.get', []), throwsArgumentError);
    await expectLater(d.dispatch('html.select', ['<a/>']), throwsArgumentError);
  });
}
