import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/host_api.dart';

import 'support.dart';

/// Runs [body] (JS returning a JSON-able value) inside the shim and decodes
/// what it returned. `H` is bound to [html] parsed as a Document.
Future<Object?> probe(String body, {String html = ''}) async {
  final services = ReplayServices();
  final js = 'const H = new Document(${jsonEncode(html)}); $body';
  final s = sessionFor(testEntry(), probeExtension(js), services);
  try {
    final r = await s.call(PluginMethod.popular, [1]);
    final items = (r! as Map)['items']! as List;
    return jsonDecode((items.single as Map)['title']! as String);
  } finally {
    await s.dispose();
  }
}

const page = '''
<!DOCTYPE html><html><head><title>T &amp; U</title></head><body>
<div id="main" class="box  wide"><p>One<p>Two &lt;b&gt;</p>
<ul><li id="episode_1"><a href="/c/1?a=1&amp;b=2" data-x=y>Ch 1</a>
<li id="episode_2"><a href='/c/2'>Ch 2</a></ul>
<img data-src="/lazy.jpg" src="/real.jpg"><br/>
<section><img src=/s.png alt="x"></section></div>
<article><span>a</span><span>b</span><section>s</section></article>
<article><span>c</span></article>
<script>if (a < b) { x = "</div>"; }</script>
<!-- comment <p>no</p> --><button></button>
</body></html>''';

void main() {
  test('parses text, entities and implied end tags', () async {
    expect(await probe('return H.select("p").map((e) => e.text);', html: page), [
      'One',
      'Two <b>',
    ]);
    expect(await probe('return H.selectFirst("title").text;', html: page), 'T & U');
    expect(await probe('return H.select("li").length;', html: page), 2);
  });

  test('selects by class, id, attribute, combinators and groups', () async {
    Future<Object?> count(String css) =>
        probe('return H.select(${jsonEncode(css)}).length;', html: page);
    expect(await count('div.box.wide'), 1);
    expect(await count('#main > ul > li'), 2);
    expect(await count('ul li[id*=episode] a'), 2);
    expect(await count('a[href^="/c/"]'), 2);
    expect(await count(r'a[href$="/2"]'), 1);
    expect(await count('img[alt=x], li'), 3);
    expect(await count('article:has(section)'), 1);
    expect(await count('span + span'), 1);
    expect(await count('span ~ section'), 1);
    expect(await count('li:nth-child(2)'), 1);
    expect(await count('article span:first-child'), 2);
    expect(await count('span:last-child'), 1);
    expect(await count('article:not(:has(section)) span'), 1);
    expect(await count('p:contains(two)'), 1);
    expect(await count('button:empty'), 1);
    expect(await count('*'), greaterThan(15));
  });

  test('a leading combinator is relative to the element', () async {
    expect(
      await probe('return H.selectFirst("#main").select("> ul").length;', html: page),
      1,
    );
    expect(
      await probe('return H.selectFirst("#main").select("> li").length;', html: page),
      0,
    );
  });

  test('misses yield empty elements, not null', () async {
    expect(
      await probe(
        'const e = H.selectFirst("nope");'
        'return [e.text, e.attr("x"), e.outerHtml, e.select("a").length,'
        ' e.selectFirst("a").text, e.children.length, e.getSrc, e.hasAttr("x"),'
        ' e.parent.text, e.nextElementSibling.text, e.localName];',
        html: page,
      ),
      ['', '', '', 0, '', 0, '', false, '', '', ''],
    );
  });

  test('attributes, getters and serialisation', () async {
    expect(
      await probe(
        'const a = H.selectFirst("a"); const img = H.selectFirst("#main > img");'
        'return [a.attr("href"), a.getHref, a.attr("DATA-X"), a.hasAttr("href"),'
        ' img.getSrc, img.getDataSrc, H.selectFirst("section").getSrc,'
        ' a.outerHtml, a.parent.attr("id"), a.parent.nextElementSibling.attr("id"),'
        ' H.selectFirst("#episode_2").previousElementSibling.attr("id"),'
        ' H.selectFirst("#main").className, a.localName, a.namespaceUri];',
        html: page,
      ),
      [
        '/c/1?a=1&b=2',
        '/c/1?a=1&b=2',
        'y',
        true,
        '/lazy.jpg',
        '/lazy.jpg',
        '/s.png',
        '<a href="/c/1?a=1&amp;b=2" data-x="y">Ch 1</a>',
        'episode_1',
        'episode_2',
        'episode_1',
        'box  wide',
        'a',
        'http://www.w3.org/1999/xhtml',
      ],
    );
  });

  test('script bodies stay raw and comments are dropped', () async {
    expect(
      await probe('return [H.select("script")[0].text, H.select("div").length,'
          ' H.selectFirst("button").innerHtml];', html: page),
      ['if (a < b) { x = "</div>"; }', 1, ''],
    );
  });

  test('document accessors', () async {
    expect(
      await probe(
        'return [H.body.localName, H.head.localName, H.documentElement.localName,'
        ' H.getElementById("main").localName, H.getElementsByClassName("box").length,'
        ' H.getElementsByTagName("li").length, H.children.length, H.parent.text,'
        ' H.selectFirst("ul").innerHtml.startsWith("<li"), H.text.indexOf("Ch 2") > 0,'
        ' H.outerHtml.startsWith("<html>"), H.attr("lang"), H.hasAttr("lang"),'
        ' H.selectFirst("#main").getElementsByClassName("x").length,'
        ' H.selectFirst("ul").children.length, H.selectFirst("ul").getElementsByTagName("A").length];',
        html: page,
      ),
      ['body', 'head', 'html', 'div', 1, 2, 1, '', true, true, true, '', false, 0, 2, 2],
    );
  });

  test('odd markup: unquoted, bare, numeric entities, stray <', () async {
    expect(
      await probe(
        'const d = new Document("<p a=1 b c=\\"x\\">1 < 2 &#65;&#x42;&bogus; &copy</p><p/>x");'
        'const p = d.selectFirst("p");'
        'return [p.attr("a"), p.hasAttr("b"), p.attr("c"), p.text, d.select("p").length];',
      ),
      ['1', true, 'x', '1 < 2 AB&bogus; ©', 2],
    );
  });

  test('unsupported selectors and xpath throw named errors', () async {
    await expectLater(
      probe('return H.select("a:hover").length;', html: page),
      throwsA(isA<PluginException>().having((e) => e.message, 'message', contains(':hover'))),
    );
    await expectLater(
      probe('return H.xpath("//a");', html: page),
      throwsA(isA<PluginException>().having((e) => e.message, 'message', contains('xpath'))),
    );
  });
}
