import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/oauth_redirect.dart';
import 'package:kartka/tracking/common/rate_limiter.dart';

/// Body of `test/fixtures/tracking-anilist/<name>.json`.
String fixtureText(String name) =>
    File('test/fixtures/tracking-anilist/$name.json').readAsStringSync();

/// A canned HTTP response.
KartkaResponse reply(
  String body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => KartkaResponse(
  statusCode: status,
  bodyBytes: Uint8List.fromList(utf8.encode(body)),
  headers: headers,
);

/// One recorded POST.
class SentRequest {
  new(this.url, this.headers, this.body);
  final Uri url;
  final Map<String, String> headers;
  final String? body;

  Map<String, Object?> get json => jsonDecode(body!) as Map<String, Object?>;
  Map<String, Object?> get variables =>
      json['variables']! as Map<String, Object?>;
}

/// Replays queued responses and records every request.
class FakeHttp implements KartkaHttp {
  final List<KartkaResponse> queue = [];
  final List<SentRequest> sent = [];

  @override
  Future<KartkaResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
  }) => throw UnsupportedError('AniList only POSTs');

  @override
  Future<KartkaResponse> post(
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    sent.add(SentRequest(url, headers, body));
    return queue.removeAt(0);
  }
}

/// In-memory [KeyValueStore].
class MemoryKv implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> get(String key) async => data[key];

  @override
  Future<void> set(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final e in data.entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };
}

/// Returns a preset redirect, or throws [error].
class FakeOAuth implements OAuthRedirect {
  new(this.redirectUri, {this.result, this.error});

  @override
  final Uri redirectUri;
  Uri? result;
  Exception? error;
  final List<Uri> opened = [];

  @override
  Future<Uri> authorize(
    Uri authorizationUrl, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    opened.add(authorizationUrl);
    final e = error;
    if (e != null) throw e;
    return result!;
  }
}

/// A limiter that never waits.
RateLimiter freeLimiter() =>
    RateLimiter(perMinute: 1000, minGap: Duration.zero, sleep: (_) async {});
