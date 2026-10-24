import 'dart:convert';
import 'dart:io';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
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
}) => FakeKartkaHttp.text(body, status: status, headers: headers);

/// Decoded GraphQL payload of a recorded request.
extension GraphQlRequest on FakeRequest {
  /// The JSON body.
  Map<String, Object?> get json => jsonDecode(body!) as Map<String, Object?>;

  /// The `variables` object.
  Map<String, Object?> get variables =>
      json['variables']! as Map<String, Object?>;
}

/// The shared [FakeKartkaHttp], answering from a queue of responses.
class QueuedHttp {
  /// Responses still to hand out, in order.
  final List<KartkaResponse> queue = [];

  /// The client under test.
  late final FakeKartkaHttp http = FakeKartkaHttp((_) => queue.removeAt(0));

  /// Every request sent so far.
  List<FakeRequest> get sent => http.requests;
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

/// Lets queued microtasks and stream events run.
Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);
