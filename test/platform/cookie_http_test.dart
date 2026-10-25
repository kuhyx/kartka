import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/cookie_http.dart';
import 'package:kartka/platform/memory/memory_platform.dart';

void main() {
  late MemoryKeyValueStore kv;
  late FakeKartkaHttp inner;
  late List<Uri> asked;

  CookieKartkaHttp client(WebViewHosts hosts) => CookieKartkaHttp(
    inner,
    hosts,
    cookieFor: (url) async {
      asked.add(url);
      return url.host == 'empty.test' ? '' : 'sid=a=b; cf=1';
    },
  );

  setUp(() {
    kv = MemoryKeyValueStore();
    inner = FakeKartkaHttp((_) => FakeKartkaHttp.text('ok'));
    asked = [];
  });

  test('hosts persist and match subdomains, not look-alikes', () async {
    final hosts = WebViewHosts(kv);
    await hosts.add(Uri.parse('https://Site.test/login'));
    await hosts.add(Uri.parse('https://site.test/again'));
    final again = WebViewHosts(kv);
    expect(await again.covers(Uri.parse('https://site.test/x')), isTrue);
    expect(await again.covers(Uri.parse('https://img.site.test/x')), isTrue);
    expect(await again.covers(Uri.parse('https://evilsite.test/x')), isFalse);
    expect(await kv.get(WebViewHosts.key), '["site.test"]');
  });

  test('a corrupt hosts entry reads as none', () async {
    await kv.set(WebViewHosts.key, '{oops');
    expect(await WebViewHosts(kv).covers(Uri.parse('https://a.test')), isFalse);
  });

  test('requests to an opened host carry the WebView cookies', () async {
    final hosts = WebViewHosts(kv);
    await hosts.add(Uri.parse('https://site.test/'));
    final http = client(hosts);
    await http.get(Uri.parse('https://site.test/c/1'));
    expect(inner.requests.single.headers['Cookie'], 'sid=a=b; cf=1');
    expect(asked.single.path, '/c/1');
  });

  test('a caller cookie is kept and merged', () async {
    final hosts = WebViewHosts(kv);
    await hosts.add(Uri.parse('https://site.test/'));
    await client(hosts)
        .get(Uri.parse('https://site.test/'), headers: {'cookie': 'mine=1'});
    expect(inner.requests.single.headers, {'cookie': 'mine=1; sid=a=b; cf=1'});
  });

  test('other hosts and empty jars pass through untouched', () async {
    final hosts = WebViewHosts(kv);
    await hosts.add(Uri.parse('https://empty.test/'));
    final http = client(hosts);
    await http.post(Uri.parse('https://other.test/'), body: 'x');
    await http.get(Uri.parse('https://empty.test/'));
    expect(inner.requests[0].headers, isEmpty);
    expect(inner.requests[0].body, 'x');
    expect(inner.requests[1].headers, isEmpty);
    expect(asked.map((u) => u.host), ['empty.test']);
  });
}
