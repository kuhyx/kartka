import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/source_health/install/source_probe.dart';

import '../../browse/fakes.dart';

void main() {
  late FakeRefreshableProvider provider;
  late SourceRegistry registry;

  setUp(() {
    provider = FakeRefreshableProvider();
    registry = SourceRegistry([provider]);
  });
  tearDown(() => registry.dispose());

  Future<String?> probe(String id) => probeSource(
    registry,
    id,
    appear: const Duration(milliseconds: 50),
    answer: const Duration(milliseconds: 50),
  );

  test(
    'passes once the source is listed and its popular page has titles',
    () async {
      final source = FakeSource('suwayomi:1');
      provider.onRefresh = [source];
      expect(await probe('suwayomi:1'), isNull);
      expect(provider.refreshes, 1);
      expect(source.calls, ['popular:1']);
    },
  );

  test('waits for a source that is listed only after the refresh', () async {
    final probing = probe('plugin:p');
    await Future<void>.delayed(Duration.zero);
    provider.controller.add([FakeSource('plugin:p')]);
    expect(await probing, isNull);
  });

  test('fails when the source never shows up', () async {
    expect(
      await probe('suwayomi:404'),
      'the source did not appear after install',
    );
  });

  test('fails when popular is empty or throws (URLs stripped)', () async {
    provider.onRefresh = [
      FakeSource('empty', perPage: 0),
      FakeSource('broken')
        ..failWith = StateError('HTTP 403 at https://site.test/a?b=c'),
    ];
    expect(await probe('empty'), 'its popular page listed no titles');
    expect(await probe('broken'), 'Bad state: HTTP 403 at <url>');
  });
}
