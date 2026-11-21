import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Keiyoushi's extension store (`repo.json` -> `index_v2`, a gzipped
/// protobuf in Mihon's `NetworkExtensionStore` shape).
const keiyoushiIndexUrl =
    'https://github.com/keiyoushi/extensions/raw/repo/index.pb';

/// SHA-256 of Keiyoushi's signing certificate (`repo.json`
/// `signingKeyFingerprint`); the Kotlin loader refuses any other signer.
const keiyoushiSigningKey =
    '9add655a78e96c4ec7a53ef89dccb557cb5d767489fac5e785d671a5a75d4da2';

/// One extension offered by the store.
class RepoExtension {
  /// Creates the entry.
  const new({
    required this.name,
    required this.pkg,
    required this.apkUrl,
    required this.iconUrl,
    required this.lib,
    required this.versionCode,
    required this.versionName,
    required this.nsfw,
    required this.sourceIds,
    required this.langs,
  });

  /// Display name (`Tachiyomi: ` stripped).
  final String name;

  /// Android package name.
  final String pkg;

  /// Where the APK downloads from.
  final String apkUrl;

  /// Launcher icon.
  final String iconUrl;

  /// Extension lib version, e.g. `1.6`.
  final String lib;

  /// Build number; an installed lower one has an update.
  final int versionCode;

  /// Version label, e.g. `1.6.38`.
  final String versionName;

  /// Whether the store flags it NSFW.
  final bool nsfw;

  /// Tachiyomi source ids (strings: they exceed 2^53).
  final List<String> sourceIds;

  /// Source languages.
  final Set<String> langs;

  /// `all` for multi-language extensions, else the one language.
  String get lang => langs.length == 1 ? langs.single : 'all';
}

/// Parses the gzipped protobuf [bytes] of [keiyoushiIndexUrl].
List<RepoExtension> parseKeiyoushiIndex(Uint8List bytes) {
  final raw = Uint8List.fromList(const GZipDecoder().decodeBytes(bytes));
  final store = _fields(raw);
  final list = store[101];
  if (list == null || list.isEmpty) return const [];
  return [
    for (final e in _fields(list.single as Uint8List)[1] ?? const [])
      _extension(_fields(e as Uint8List)),
  ];
}

RepoExtension _extension(Map<int, List<Object>> f) {
  final res = _fields(f[3]!.single as Uint8List);
  final sources = [for (final s in f[8] ?? const []) _fields(s as Uint8List)];
  return RepoExtension(
    name: _str(f, 1).replaceFirst('Tachiyomi: ', ''),
    pkg: _str(f, 2),
    apkUrl: _str(res, 1),
    iconUrl: _str(res, 2),
    lib: _str(f, 4),
    versionCode: _int(f, 5),
    versionName: _str(f, 6),
    nsfw: _int(f, 7) == 3,
    sourceIds: [for (final s in sources) _uint64(s[1]?.single)],
    langs: {for (final s in sources) _str(s, 3)},
  );
}

String _str(Map<int, List<Object>> f, int n) {
  final v = f[n]?.single;
  return v is Uint8List ? utf8.decode(v) : '';
}

int _int(Map<int, List<Object>> f, int n) {
  final v = f[n]?.single;
  return v is BigInt ? v.toInt() : 0;
}

/// A protobuf int64 as an unsigned decimal string would misread negative
/// ids; Tachiyomi ids are signed longs, so decode two's complement.
String _uint64(Object? v) {
  if (v is! BigInt) return '0';
  return v.toSigned(64).toString();
}

/// Field number -> values: varints as [BigInt], length-delimited as bytes.
Map<int, List<Object>> _fields(Uint8List b) {
  final out = <int, List<Object>>{};
  var i = 0;
  BigInt varint() {
    var result = BigInt.zero;
    var shift = 0;
    while (true) {
      final byte = b[i++];
      result |= BigInt.from(byte & 0x7f) << shift;
      if (byte < 0x80) return result;
      shift += 7;
    }
  }

  while (i < b.length) {
    final key = varint().toInt();
    final Object value;
    switch (key & 7) {
      case 0:
        value = varint();
      case 2:
        final len = varint().toInt();
        value = Uint8List.sublistView(b, i, i + len);
        i += len;
      case 1:
        i += 8;
        continue;
      case 5:
        i += 4;
        continue;
      default:
        throw FormatException('protobuf wire type ${key & 7}');
    }
    (out[key >> 3] ??= []).add(value);
  }
  return out;
}
