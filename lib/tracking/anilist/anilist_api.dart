import 'dart:convert';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/tracking/anilist/anilist_parse.dart';
import 'package:kartka/tracking/anilist/anilist_queries.dart';
import 'package:kartka/tracking/common/rate_limiter.dart';

/// Rate-limited GraphQL transport for AniList.
///
/// Every request first takes a [RateLimiter] slot (AniList allows 90/min,
/// 30/min while degraded; we default to 30). Rate-limit headers feed back
/// into the limiter, and a 429 is retried after its `Retry-After`.
class AniListApi {
  /// Creates the transport over the platform HTTP client.
  new(this._http, {RateLimiter? limiter, this.maxRetries = 2})
    : limiter = limiter ?? RateLimiter(perMinute: 30);

  final KartkaHttp _http;

  /// The client-side limiter every request goes through.
  final RateLimiter limiter;

  /// How many times a 429 is retried before giving up.
  final int maxRetries;

  /// Runs [query] with [variables]; returns the decoded JSON body.
  /// Throws [AniListException] when the body carries GraphQL errors.
  Future<Map<String, Object?>> call(
    String query,
    Map<String, Object?> variables, {
    String? token,
  }) async {
    for (var attempt = 0; ; attempt++) {
      await limiter.acquire();
      final res = await _http.post(
        aniListEndpoint,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': query, 'variables': variables}),
      );
      final retryAfter = int.tryParse(res.headers['retry-after'] ?? '');
      limiter.observe(
        remaining: int.tryParse(res.headers['x-ratelimit-remaining'] ?? ''),
        retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
      );
      if (res.statusCode == 429 && attempt < maxRetries) continue;
      return _decode(res);
    }
  }

  Map<String, Object?> _decode(KartkaResponse res) {
    Object? body;
    try {
      body = jsonDecode(res.body);
    } on FormatException {
      body = null;
    }
    if (body is Map<String, Object?>) return body;
    throw AniListException(
      'HTTP ${res.statusCode}: not a GraphQL body',
      status: res.statusCode,
    );
  }
}
