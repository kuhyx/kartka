import 'dart:convert';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/sources/mangadex/mangadex_mapper.dart';
import 'package:kartka/sources/mangadex/mangadex_parse.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';
import 'package:kartka/sources/mangadex/mangadex_urls.dart';
import 'package:kartka/sources/mangadex/rate_limiter.dart';

/// A MangaDex API error (non-2xx with MangaDex's error body).
class MangadexApiException extends KartkaHttpException {
  /// Creates the exception with the API's [message].
  const new(super.url, super.statusCode, this.message);

  /// `errors[0].detail` of the response, or a generic text.
  final String message;

  @override
  String toString() => 'MangadexApiException($statusCode, $message, $url)';
}

/// Native source over MangaDex's official API (`api.mangadex.org`).
class MangaDexSource implements MangaSource {
  /// Creates the source; [limiter] defaults to MangaDex's documented limits.
  new({
    required this._http,
    required this._settings,
    RateLimiter? limiter,
    DateTime Function()? now,
    this.feedLimit = MangadexUrls.feedLimit,
    this.maxRetries = 2,
  }) : _now = now ?? DateTime.now,
       _limiter = limiter ?? RateLimiter(mangadexRateRules, now: now);

  /// Headers every API and image request carries.
  static const Map<String, String> headers = {'User-Agent': kartkaUserAgent};

  /// Chapters per feed request.
  final int feedLimit;

  /// How often a 429 is retried after its back-off.
  final int maxRetries;

  final KartkaHttp _http;
  final MangadexSettingsStore _settings;
  final RateLimiter _limiter;
  final DateTime Function() _now;

  @override
  SourceRef get ref => const SourceRef(
    id: mangadexSourceId,
    name: mangadexSourceName,
    lang: 'all',
    origin: SourceOrigin.native,
  );

  Future<(MangadexUrls, MangadexMapper)> _ctx() async {
    await _settings.ready;
    final s = _settings.value;
    return (MangadexUrls(s), MangadexMapper(s));
  }

  @override
  Future<SearchPage> popular(int page) => _browse(page, (u) => u.popular(page));

  @override
  Future<SearchPage> latest(int page) => _browse(page, (u) => u.latest(page));

  @override
  Future<SearchPage> search(String query, int page) =>
      _browse(page, (u) => u.search(query, page));

  Future<SearchPage> _browse(int page, Uri Function(MangadexUrls) url) async {
    final (urls, map) = await _ctx();
    final offset = MangadexUrls.offsetOf(page);
    if (offset + MangadexUrls.pageSize > MangadexUrls.maxWindow) {
      return SearchPage.empty;
    }
    return map.page(await _get(url(urls)), offset);
  }

  @override
  Future<MangaDetails> details(String mangaUrl) async {
    final (urls, map) = await _ctx();
    final body = await _get(urls.details(MangadexUrls.idOf(mangaUrl)));
    return map.details(body['data']! as Json);
  }

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    final (urls, map) = await _ctx();
    final id = MangadexUrls.idOf(mangaUrl);
    final out = <ChapterInfo>[];
    var offset = 0;
    for (;;) {
      final body = await _get(urls.feed(id, offset: offset, limit: feedLimit));
      final data = (body['data'] as List<Object?>? ?? const []).cast<Json>();
      out.addAll(data.map(map.chapter));
      offset += data.length;
      final total = (body['total'] as num?)?.toInt() ?? 0;
      if (data.isEmpty || offset >= total) return List.unmodifiable(out);
    }
  }

  /// Fetched fresh every time: an at-home `baseUrl` expires in minutes.
  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    final (urls, map) = await _ctx();
    final body = await _get(urls.atHome(MangadexUrls.idOf(chapterUrl)));
    return map.pages(body, headers);
  }

  Future<Json> _get(Uri url) async {
    for (var attempt = 0; ; attempt++) {
      await _limiter.acquire(url);
      final res = await _http.get(url, headers: headers);
      if (res.statusCode == 429 && attempt < maxRetries) {
        _limiter.backOff(url.host, _retryAt(res));
        continue;
      }
      final body = _decode(res.body);
      if (res.ok) return body;
      throw MangadexApiException(url, res.statusCode, apiError(body));
    }
  }

  /// `X-RateLimit-Retry-After` is a Unix timestamp in seconds.
  DateTime _retryAt(KartkaResponse res) {
    final secs = int.tryParse(res.headers['x-ratelimit-retry-after'] ?? '');
    if (secs == null) return _now().add(const Duration(seconds: 1));
    return DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
  }

  static Json _decode(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is Json ? v : const {};
    } on FormatException {
      return const {};
    }
  }
}
