// Fixture plugin: the chapter's page list only exists after the page's own
// JS runs, so pages() reads it through the browser engine.
function popular(page) { return { items: [], hasNext: false }; }
function latest(page) { return { items: [], hasNext: false }; }
function search(query, page) { return { items: [], hasNext: false }; }
function details(url) { return { url: url, title: 'JS Pages' }; }
function chapters(url) { return [{ url: url, name: 'Chapter 1', number: 1 }]; }
async function pages(url) {
  var r = await kartka.browser.load(url, { waitFor: '#pages img', timeoutMs: 15000 });
  return kartka.html.select(r.html, '#pages img').map(function (e) {
    return { imageUrl: e.attrs.src, headers: { Referer: r.url } };
  });
}
