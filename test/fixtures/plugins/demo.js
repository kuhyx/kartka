// Sample Kartka plugin (apiVersion 1) for a fictional site, used by tests.
var BASE = 'https://demo.test';

async function list(path) {
  var r = await kartka.http.get(BASE + path);
  var rows = kartka.html.select(r.body, 'li.manga a');
  var next = kartka.html.select(r.body, 'a.next');
  return {
    items: rows.map(function (a) {
      return { url: a.attrs.href, title: a.text, coverUrl: BASE + a.attrs['data-cover'] };
    }),
    hasNext: next.length > 0
  };
}

function popular(page) { return list('/popular?page=' + page); }
function latest(page) { return list('/latest?page=' + page); }
function search(query, page) {
  return list('/search?q=' + encodeURIComponent(query) + '&page=' + page);
}

async function details(url) {
  var r = await kartka.http.get(BASE + url);
  var title = kartka.html.select(r.body, 'h1');
  var desc = kartka.html.select(r.body, 'p.desc');
  var genres = kartka.html.select(r.body, 'span.genre');
  kartka.log('details', url);
  return {
    url: url,
    title: title[0].text,
    description: desc[0].text,
    genres: genres.map(function (g) { return g.text; }),
    authors: ['Demo Author'],
    status: 'ongoing'
  };
}

async function chapters(url) {
  var r = await kartka.http.get(BASE + url);
  var rows = kartka.html.select(r.body, 'ul.chapters a');
  return rows.map(function (a) {
    return { url: a.attrs.href, name: a.text, number: parseFloat(a.attrs['data-n']) };
  });
}

async function pages(url) {
  var r = await kartka.http.get(BASE + url);
  var imgs = kartka.html.select(r.body, 'img.page');
  var seen = (await kartka.prefs.get('seen')) || '0';
  await kartka.prefs.set('seen', String(Number(seen) + 1));
  return imgs.map(function (i) {
    return { imageUrl: i.attrs.src, headers: { Referer: BASE + '/' } };
  });
}

function boom() { throw new Error('boom'); }
