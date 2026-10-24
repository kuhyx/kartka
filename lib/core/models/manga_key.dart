import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Stable across devices: `'<sourceId>|<mangaUrl>'` (DOCS-contracts §1).
typedef MangaKey = String;

/// Builds the [MangaKey] for the manga at [url] in source [sourceId].
MangaKey mangaKeyOf(String sourceId, String url) => '$sourceId|$url';

/// RTDB-safe key (§4): lowercase hex SHA-1 of the key's UTF-8 bytes.
///
/// The same hash serves `chapterUrlHash` and `sourceIdHash` (pass the
/// chapter URL / source id).
String mangaKeyHash(MangaKey key) => sha1.convert(utf8.encode(key)).toString();
