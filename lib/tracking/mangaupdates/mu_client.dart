/// Rate-limited JSON transport for the MangaUpdates API v1, over KartkaHttp.
library;

import 'dart:convert';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/tracking/common/rate_limiter.dart';

/// API base URL (servers[0] of https://api.mangaupdates.com/openapi.yaml).
const muApiBase = 'https://api.mangaupdates.com/v1';

/// Wait used when a 412/429 carries no usable `Retry-After`.
const muDefaultBackoff = Duration(seconds: 5);

/// Sends MangaUpdates requests politely.
///
/// The API's acceptable-use policy asks for "reasonable spacing between
/// requests", and every list write answers 412 "Five second update delay"
/// when sent sooner than 5 s after the previous one. So every call goes
/// through [reads] (1 s gap) and list writes also through [writes] (5 s
/// gap). A 429 or 412 is retried up to [maxRetries] times after
/// `Retry-After` seconds, or an exponential back-off from 5 s; the wait is
/// fed into both limiters so concurrent callers hold off too.
class MuClient {
  /// Creates a client sending through [_http].
  new({
    required this._http,
    RateLimiter? reads,
    RateLimiter? writes,
    this.maxRetries = 3,
  }) : reads =
           reads ??
           RateLimiter(perMinute: 30, minGap: const Duration(seconds: 1)),
       writes =
           writes ??
           RateLimiter(perMinute: 12, minGap: const Duration(seconds: 5));

  final KartkaHttp _http;

  /// Limiter every request passes.
  final RateLimiter reads;

  /// Extra limiter for list writes.
  final RateLimiter writes;

  /// Retries after a 429/412 before the response is returned as is.
  final int maxRetries;

  /// Sends [method] to [path] (relative to [muApiBase]) with an optional
  /// [json] body and bearer [token]. Set [write] for list mutations.
  Future<KartkaResponse> send(
    String method,
    String path, {
    Object? json,
    String? token,
    bool write = false,
  }) async {
    final headers = {
      'Accept': 'application/json',
      'Content-Type': ?(json == null ? null : 'application/json'),
      'Authorization': ?(token == null ? null : 'Bearer $token'),
    };
    final body = json == null ? null : jsonEncode(json);
    final url = Uri.parse('$muApiBase$path');
    for (var attempt = 0; ; attempt++) {
      await reads.acquire();
      if (write) await writes.acquire();
      final res = await _http.send(method, url, headers: headers, body: body);
      final limited = res.statusCode == 429 || res.statusCode == 412;
      if (!limited || attempt >= maxRetries) return res;
      final wait = _retryAfter(res) ?? muDefaultBackoff * (1 << attempt);
      reads.observe(retryAfter: wait);
      writes.observe(retryAfter: wait);
    }
  }

  static Duration? _retryAfter(KartkaResponse res) {
    final seconds = int.tryParse(res.headers['retry-after'] ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
