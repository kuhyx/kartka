// Shared fakes for the MangaUpdates tests.
//
// The fixtures under test/fixtures/tracking-mangaupdates/ were built from the
// official OpenAPI spec (https://api.mangaupdates.com/openapi.yaml, v1.0.0,
// fetched 2026-10-24): ApiResponseV1, ListsSeriesModelV1 and
// SeriesSearchResponseV1. `context.session_token` (ApiContextV1 is
// free-form in the spec) follows Mihon's MangaUpdates tracker. Series ids are
// real: base36 of the id is the slug in the series url.
import 'dart:convert';
import 'dart:io';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/rate_limiter.dart';
import 'package:kartka/tracking/mangaupdates/mu_api.dart';
import 'package:kartka/tracking/mangaupdates/mu_client.dart';
import 'package:kartka/tracking/mangaupdates/mu_session.dart';

/// Reads a fixture body from test/fixtures/tracking-mangaupdates/.
String fixture(String name) =>
    File('test/fixtures/tracking-mangaupdates/$name').readAsStringSync();

/// A response with fixture [name] as body.
KartkaResponse fx(
  String name, {
  int status = 200,
  Map<String, String> headers = const {},
}) => FakeKartkaHttp.text(fixture(name), status: status, headers: headers);

/// JSON request body of [r], decoded.
Object? jsonBody(FakeRequest r) => jsonDecode(r.body!);

/// A clock that only moves when something sleeps on it.
class FakeClock {
  /// Time now.
  DateTime now = DateTime.utc(2026, 10, 24, 12);

  /// Every sleep requested, in order.
  final List<Duration> sleeps = [];

  /// Sleeps by advancing [now].
  Future<void> sleep(Duration d) async {
    sleeps.add(d);
    now = now.add(d);
  }

  /// A limiter on this clock.
  RateLimiter limiter({required int perMinute, required Duration minGap}) =>
      RateLimiter(
        perMinute: perMinute,
        minGap: minGap,
        now: () => now,
        sleep: sleep,
      );
}

/// The client/store/api stack on [http] and [clock].
({MuClient client, MuSessionStore store, MuApi api, MemoryKeyValueStore kv})
buildStack(FakeKartkaHttp http, FakeClock clock) {
  final client = MuClient(
    http: http,
    reads: clock.limiter(perMinute: 1000, minGap: Duration.zero),
    writes: clock.limiter(perMinute: 1000, minGap: const Duration(seconds: 5)),
  );
  final kv = MemoryKeyValueStore();
  final store = MuSessionStore(kv);
  return (
    client: client,
    store: store,
    api: MuApi(client: client, store: store),
    kv: kv,
  );
}

/// A stored session for tests that start logged in.
const testSession = MuSession(token: 'tok', username: 'kuhy');
