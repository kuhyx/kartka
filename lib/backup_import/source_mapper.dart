import 'dart:convert';

import 'package:crypto/crypto.dart';

/// How a Tachiyomi source ended up mapped.
enum SourceKind {
  /// Claimed by a Kartka-native (or overridden) source.
  native,

  /// Served through Suwayomi, which keeps Tachiyomi's numeric ids.
  suwayomi,

  /// Tachiyomi's local source.
  local,

  /// SY-internal source Suwayomi cannot run (E-Hentai, merged, ...). The
  /// entry is still imported, as `suwayomi:<id>`, but flagged in the summary.
  unmapped,
}

/// Result of mapping one Tachiyomi source id.
class MappedSource {
  /// Creates a mapping result.
  const MappedSource(this.sourceId, this.kind);

  /// Kartka source id (`mangadex`, `local`, `suwayomi:<id>`, ...).
  final String sourceId;

  /// How it was mapped.
  final SourceKind kind;
}

/// MangaDex languages published by the Keiyoushi extension
/// (`src/all/mangadex/build.gradle.kts`), one Tachiyomi source each.
final List<String> mangaDexLanguages = _languages.split(' ');

const String _languages =
    'af sq ar az eu be bn bg my ca zh-Hans zh-Hant cv hr cs da nl '
    'en eo et fil fi fr ka de el he hi hu ga id it ja jv kk ko la '
    'lt ms mn ne no fa pl pt-BR pt ro ru sr sk es-419 es sv ta te '
    'th tr uk ur uz vi';

/// Tachiyomi's `HttpSource.generateId`: the first 8 bytes of
/// `md5("<name lowercased>/<lang>/<versionId>")` as a non-negative int64.
/// Returned as a decimal string (int64 does not fit a dart2js int).
String tachiyomiSourceId(String name, String lang, {int version = 1}) {
  final digest = md5.convert(
    utf8.encode('${name.toLowerCase()}/$lang/$version'),
  );
  final top = digest.bytes
      .take(8)
      .fold(BigInt.zero, (a, b) => (a << 8) | BigInt.from(b));
  return (top & ((BigInt.one << 63) - BigInt.one)).toString();
}

/// Decimal ids of every per-language MangaDex source.
final Set<String> mangaDexSourceIds = {
  for (final lang in mangaDexLanguages) tachiyomiSourceId('MangaDex', lang),
};

/// Tachiyomi's local source id.
const String _localId = '0';

/// SY sources with no Suwayomi counterpart: E-Hentai, ExHentai, merged.
const Set<String> _syInternalIds = {'6901', '6902', '6969'};

/// Maps Tachiyomi numeric source ids to Kartka source ids.
///
/// MangaDex keeps its manga/chapter URLs (`/manga/<uuid>`, `/chapter/<uuid>`)
/// because the native source uses the Keiyoushi URL shape, so only the source
/// id changes. [overrides] (Tachiyomi id to Kartka id) beat every default.
class SourceMapper {
  /// Creates a mapper.
  const SourceMapper({this.overrides = const {}});

  /// Explicit Tachiyomi id to Kartka source id replacements.
  final Map<String, String> overrides;

  /// Maps [tachiyomiId] (decimal string).
  MappedSource map(String tachiyomiId) {
    final override = overrides[tachiyomiId];
    if (override != null) return MappedSource(override, SourceKind.native);
    if (mangaDexSourceIds.contains(tachiyomiId)) {
      return const MappedSource('mangadex', SourceKind.native);
    }
    if (tachiyomiId == _localId) {
      return const MappedSource('local', SourceKind.local);
    }
    final kind = _syInternalIds.contains(tachiyomiId)
        ? SourceKind.unmapped
        : SourceKind.suwayomi;
    return MappedSource('suwayomi:$tachiyomiId', kind);
  }
}
