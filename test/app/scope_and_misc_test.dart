import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/app/scope.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/platform/platform.dart';

import '../helpers/fake_platform.dart';

void main() {
  testWidgets('KartkaScope notifies only when registry or platform change', (
    tester,
  ) async {
    final platform = fakePlatform();
    final registry = KartkaRegistry([]);
    final scope = KartkaScope(
      registry: registry,
      platform: platform,
      child: const SizedBox(),
    );
    expect(
      scope.updateShouldNotify(
        KartkaScope(
          registry: registry,
          platform: platform,
          child: const SizedBox(),
        ),
      ),
      isFalse,
    );
    expect(
      scope.updateShouldNotify(
        KartkaScope(
          registry: KartkaRegistry([]),
          platform: platform,
          child: const SizedBox(),
        ),
      ),
      isTrue,
    );
  });

  test('StaticSourceProvider emits its fixed set once', () async {
    final provider = StaticSourceProvider([]);
    expect(await provider.watch().toList(), [isEmpty]);
    expect(provider.sources.clear, throwsUnsupportedError);
  });

  test('FakeOAuthRedirect defaults to the bare redirect', () async {
    final back = await FakeOAuthRedirect().authorize(Uri.parse('https://a/'));
    expect(back, Uri.parse('kartka://oauth'));
    final web = FakeOAuthRedirect(
      null,
      Uri.parse('http://127.0.0.1:8791/oauth'),
    );
    expect(web.redirectUri.port, 8791);
    expect(await web.authorize(Uri.parse('https://a/')), web.redirectUri);
    // A runtime (non-const) instance, so the constructor itself runs.
    final cancelled = [OAuthCancelled.new][0]();
    expect(cancelled, isA<Exception>());
  });
}
