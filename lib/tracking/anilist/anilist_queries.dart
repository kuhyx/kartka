/// GraphQL documents sent to `https://graphql.anilist.co`.
library;

/// AniList GraphQL endpoint.
final Uri aniListEndpoint = Uri.parse('https://graphql.anilist.co');

/// Implicit-grant authorize endpoint (token comes back in the fragment).
final Uri aniListAuthorize = Uri.parse(
  'https://anilist.co/api/v2/oauth/authorize',
);

/// Manga search, best match first. Variables: `search`.
const searchQuery = r'''
query ($search: String) {
  Page(page: 1, perPage: 20) {
    media(search: $search, type: MANGA, sort: SEARCH_MATCH) {
      id chapters
      title { userPreferred english romaji }
      coverImage { large }
    }
  }
}''';

/// The viewer's list entry for one manga. Variables: `id`.
const fetchQuery = r'''
query ($id: Int) {
  Media(id: $id, type: MANGA) {
    id chapters
    mediaListEntry { id progress status score(format: POINT_10_DECIMAL) }
  }
}''';

/// Creates or updates the viewer's list entry. Variables: `mediaId`,
/// `progress`, optional `status`.
const saveMutation = r'''
mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus) {
  SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status) {
    id progress status
  }
}''';
