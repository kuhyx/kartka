import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/browser_engine.dart';
import 'package:kartka/platform/engine_core.dart';
import 'package:kartka/platform/engine_scripts.dart';

/// A scripted page: each probe pops the next state (the last one repeats).
class ScriptedPage implements EnginePage {
  new(this.states, {this.snapshot = const {}, this.failProbes = 0});

  final List<Map<String, Object?>> states;
  final Map<String, Object?> snapshot;
  int failProbes;
  final navigations = <(Uri, Map<String, String>)>[];
  final evaluated = <String>[];
  bool closed = false;
  int _i = 0;

  @override
  Future<void> navigate(Uri url, Map<String, String> headers) async =>
      navigations.add((url, headers));

  @override
  Future<Object?> evaluate(String js) async {
    evaluated.add(js);
    if (js.startsWith(kEngineProbeMarker)) {
      if (failProbes > 0) {
        failProbes--;
        throw StateError('execution context destroyed');
      }
      final s = states[_i < states.length ? _i : states.length - 1];
      _i++;
      return jsonEncode(s);
    }
    if (js == kEngineSnapshotJs) return jsonEncode(snapshot);
    return null;
  }

  @override
  Future<void> close() async => closed = true;
}

Map<String, Object?> state({
  String ready = 'complete',
  bool ran = true,
  bool matched = true,
  String? response,
  String? challenge,
  String href = 'https://site.test/c/1',
}) => {
  'ready': ready,
  'ran': ran,
  'matched': matched,
  'response': response,
  'challenge': challenge,
  'href': href,
};

const Map<String, Object?> snap = {
  'html': '<html><body><img src="a.jpg"></body></html>',
  'resources': ['https://site.test/a.jpg', 'https://site.test/app.js'],
  'status': 200,
  'href': 'https://site.test/c/1',
};

EngineCore core(ScriptedPage page) =>
    EngineCore(() async => page, pollInterval: Duration.zero);

void main() {
  final url = Uri.parse('https://site.test/c/1');

  test('runs scripts once the document completes, then snapshots', () async {
    final page = ScriptedPage([
      state(ready: 'loading', ran: false, matched: false),
      state(ran: false, matched: false),
      state(matched: false),
      state(),
    ], snapshot: snap);
    final r = await core(page).load(
      EngineRequest(
        url: url,
        headers: const {'Referer': 'https://site.test/', 'User-Agent': 'x'},
        scripts: const ['window.a = 1;'],
        waitFor: '#pages img',
      ),
    );
    expect(page.navigations.single.$2, {'Referer': 'https://site.test/'});
    expect(page.evaluated.where((js) => js == kEngineHookJs), hasLength(1));
    expect(page.evaluated, contains('window.a = 1;'));
    expect(page.evaluated.last, kEngineSnapshotJs);
    expect(r.html, contains('a.jpg'));
    expect(r.resources, hasLength(2));
    expect(r.status, 200);
    expect(r.url, url);
    expect(r.timedOut, isFalse);
    expect(page.closed, isTrue);
  });

  test('awaitResponse waits for the page response', () async {
    final page = ScriptedPage([
      state(),
      state(response: 'payload'),
    ], snapshot: snap);
    final r = await core(page)
        .load(EngineRequest(url: url, awaitResponse: true));
    expect(r.response, 'payload');
  });

  test('a challenge throws ChallengeRequired and closes the page', () async {
    final page = ScriptedPage([
      state(ran: false, challenge: 'cloudflare', href: 'https://site.test/x'),
    ]);
    await expectLater(
      core(page).load(EngineRequest(url: url)),
      throwsA(
        isA<ChallengeRequired>()
            .having((c) => c.kind, 'kind', 'cloudflare')
            .having((c) => c.url.path, 'url', '/x'),
      ),
    );
    expect(page.evaluated.where((js) => js == kEngineHookJs), isEmpty);
    expect(page.closed, isTrue);
  });

  test('the deadline returns the snapshot as timedOut', () async {
    final page = ScriptedPage([state(matched: false)], snapshot: snap);
    final r =
        await EngineCore(
          () async => page,
          pollInterval: const Duration(milliseconds: 5),
        ).load(
          EngineRequest(
            url: url,
            waitFor: '.never',
            timeout: const Duration(milliseconds: 30),
          ),
        );
    expect(r.timedOut, isTrue);
    expect(r.response, isNull);
  });

  test('probe errors during navigation are retried', () async {
    final page = ScriptedPage([state()], snapshot: snap, failProbes: 2);
    final r = await core(page).load(EngineRequest(url: url));
    expect(r.timedOut, isFalse);
  });

  test('a bad snapshot still yields an empty result', () async {
    final page = ScriptedPage([state()], snapshot: const {'html': 3});
    final r = await core(page).load(EngineRequest(url: url));
    expect(r.html, '');
    expect(r.resources, isEmpty);
    expect(r.status, isNull);
    expect(r.url, url);
  });

  test('refuses loopback and non-http URLs before opening a page', () async {
    final page = ScriptedPage([state()]);
    for (final bad in [
      'http://127.0.0.1:47391/',
      'http://localhost/x',
      'http://[::1]/',
      'http://0.0.0.0:47391/',
      'file:///etc/passwd',
      'javascript:alert(1)',
    ]) {
      await expectLater(
        core(page).load(EngineRequest(url: Uri.parse(bad))),
        throwsArgumentError,
        reason: bad,
      );
    }
    expect(page.navigations, isEmpty);
    expect(isEngineUrlAllowed(Uri.parse('data:text/html,<p>x</p>')), isTrue);
  });

  test('the pre-navigation document and error pages are not ready', () async {
    final page = ScriptedPage([
      state(ran: false, href: 'about:blank'),
      state(ran: false, href: 'chrome-error://chromewebdata/'),
      state(ran: false, href: '::'),
      state(ran: false),
      state(response: 'r'),
    ], snapshot: snap);
    final r = await core(page).load(
      EngineRequest(url: url, scripts: const ['go()'], awaitResponse: true),
    );
    expect(r.response, 'r');
    // The hook ran once, on the real document only.
    expect(page.evaluated.where((js) => js == kEngineHookJs), hasLength(1));
    expect(page.evaluated.indexOf(kEngineHookJs), 4);
  });

  test('a redirect onto a forbidden origin stops before any script', () async {
    final page = ScriptedPage([
      state(ran: false, href: 'http://127.0.0.1:47391/'),
    ]);
    await expectLater(
      core(page).load(EngineRequest(url: url, scripts: const ['steal()'])),
      throwsA(isA<StateError>()),
    );
    expect(page.evaluated, isNot(contains(kEngineHookJs)));
    expect(page.evaluated, isNot(contains('steal()')));
    expect(page.closed, isTrue);
  });

  test('timeouts are clamped to the maximum', () {
    final r = EngineRequest(url: url, timeout: const Duration(minutes: 5));
    expect(r.timeout, EngineRequest.maxTimeout);
  });
}
