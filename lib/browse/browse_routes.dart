/// Browse-owned route paths (the detail and reader routes live in
/// `lib/app/routes.dart`). Source ids are `Uri.encodeComponent`-encoded.
library;

/// Path pattern of a source's popular/latest/search screen.
const sourceRoutePattern = '/browse/source/:sourceId';

/// Path pattern of the all-sources search screen.
const globalSearchRoutePattern = '/browse/search';

/// Path of [sourceId]'s browse screen, optionally opened on a search.
String sourceRoute(String sourceId, {String? query}) => Uri(
  path: '/browse/source/${Uri.encodeComponent(sourceId)}',
  queryParameters: query == null ? null : {'q': query},
).toString();

/// Path of the global search for [query].
String globalSearchRoute(String query) =>
    Uri(path: globalSearchRoutePattern, queryParameters: {'q': query})
        .toString();
