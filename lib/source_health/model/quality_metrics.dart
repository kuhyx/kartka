/// §5 blocks about what a source serves: chapter completeness, image
/// quality and whether it duplicates a better source.
library;

import 'package:flutter/foundation.dart';
import 'package:kartka/source_health/model/json_read.dart';

/// §5 `chapterCompleteness`: source chapters / AniList chapters, capped at 1.
@immutable
class CompletenessMetric {
  /// Creates a completeness block.
  const new({this.sampled, this.medianRatio});

  /// Parses `chapterCompleteness`; null unless [json] is a map.
  static CompletenessMetric? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    return CompletenessMetric(
      sampled: readInt(m, 'sampled'),
      medianRatio: readDouble(m, 'medianRatio'),
    );
  }

  /// Reference titles sampled.
  final int? sampled;

  /// Median completeness over the sample.
  final double? medianRatio;

  /// The JSON block.
  Map<String, Object?> toJson() =>
      compact({'sampled': sampled, 'medianRatio': medianRatio});

  @override
  bool operator ==(Object other) =>
      other is CompletenessMetric &&
      other.sampled == sampled &&
      other.medianRatio == medianRatio;

  @override
  int get hashCode => Object.hash(sampled, medianRatio);
}

/// §5 `imageQuality`: median page width and JPEG quality.
@immutable
class ImageQualityMetric {
  /// Creates an image-quality block.
  const new({this.sampledPages, this.medianWidthPx, this.medianJpegQuality});

  /// Parses `imageQuality`; null unless [json] is a map.
  static ImageQualityMetric? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    return ImageQualityMetric(
      sampledPages: readInt(m, 'sampledPages'),
      medianWidthPx: readInt(m, 'medianWidthPx'),
      medianJpegQuality: readInt(m, 'medianJpegQuality'),
    );
  }

  /// Pages sampled.
  final int? sampledPages;

  /// Median page width in pixels.
  final int? medianWidthPx;

  /// Median estimated JPEG quality (0-100).
  final int? medianJpegQuality;

  /// The JSON block.
  Map<String, Object?> toJson() => compact({
    'sampledPages': sampledPages,
    'medianWidthPx': medianWidthPx,
    'medianJpegQuality': medianJpegQuality,
  });

  @override
  bool operator ==(Object other) =>
      other is ImageQualityMetric &&
      other.sampledPages == sampledPages &&
      other.medianWidthPx == medianWidthPx &&
      other.medianJpegQuality == medianJpegQuality;

  @override
  int get hashCode =>
      Object.hash(sampledPages, medianWidthPx, medianJpegQuality);
}

/// §5 `subsetOf`: a higher-ranked source that already has this one's titles.
@immutable
class SubsetOfMetric {
  /// Creates a subset block.
  const new({required this.sourceId, this.overlap});

  /// Parses `subsetOf`; null unless [json] is a map with a `sourceId`.
  static SubsetOfMetric? fromJson(Object? json) {
    final m = asMap(json);
    final id = m == null ? null : readString(m, 'sourceId');
    if (id == null) return null;
    return SubsetOfMetric(sourceId: id, overlap: readDouble(m!, 'overlap'));
  }

  /// The covering source's id.
  final String sourceId;

  /// Share of this source's found titles the covering source also has.
  final double? overlap;

  /// The JSON block.
  Map<String, Object?> toJson() =>
      compact({'sourceId': sourceId, 'overlap': overlap});

  @override
  bool operator ==(Object other) =>
      other is SubsetOfMetric &&
      other.sourceId == sourceId &&
      other.overlap == overlap;

  @override
  int get hashCode => Object.hash(sourceId, overlap);
}

/// §5 `availability`: which implementations of this site exist.
@immutable
class AvailabilityMetric {
  /// Creates an availability block; null flags were not reported.
  const new({this.native, this.mangayomiJs, this.keiyoushi});

  /// Parses `availability`; null unless [json] is a map.
  static AvailabilityMetric? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    bool? flag(String k) => m[k] is bool ? m[k]! as bool : null;
    return AvailabilityMetric(
      native: flag('native'),
      mangayomiJs: flag('mangayomiJs'),
      keiyoushi: flag('keiyoushi'),
    );
  }

  /// A native Dart source exists in Kartka.
  final bool? native;

  /// A Mangayomi JS extension exists (usable as a converted plugin).
  final bool? mangayomiJs;

  /// A Keiyoushi extension exists (usable through Suwayomi).
  final bool? keiyoushi;

  /// The JSON block.
  Map<String, Object?> toJson() => compact({
    'native': native,
    'mangayomiJs': mangayomiJs,
    'keiyoushi': keiyoushi,
  });

  @override
  bool operator ==(Object other) =>
      other is AvailabilityMetric &&
      other.native == native &&
      other.mangayomiJs == mangayomiJs &&
      other.keiyoushi == keiyoushi;

  @override
  int get hashCode => Object.hash(native, mangayomiJs, keiyoushi);
}

/// `pagesLoad`: share of sampled chapter pages whose images downloaded.
@immutable
class PagesLoadMetric {
  /// Creates a pages-load block; a null [ratio] was not measured.
  const new({this.ratio, this.sampled});

  /// Parses `pagesLoad`; null unless [json] is a map.
  static PagesLoadMetric? fromJson(Object? json) {
    final m = asMap(json);
    if (m == null) return null;
    return PagesLoadMetric(
      ratio: readDouble(m, 'ratio'),
      sampled: readInt(m, 'sampled'),
    );
  }

  /// Share of sampled pages that loaded (0..1).
  final double? ratio;

  /// Pages sampled.
  final int? sampled;

  /// The JSON block.
  Map<String, Object?> toJson() =>
      compact({'ratio': ratio, 'sampled': sampled});

  @override
  bool operator ==(Object other) =>
      other is PagesLoadMetric &&
      other.ratio == ratio &&
      other.sampled == sampled;

  @override
  int get hashCode => Object.hash(ratio, sampled);
}

/// `plugin`: the Kartka plugin that reads a plugin-origin source, and the
/// repo index serving it (what an Install button needs).
@immutable
class PluginInstallRef {
  /// Creates a reference.
  const new({required this.repo, required this.id});

  /// Parses `plugin`; null unless [json] has string `repo` and `id`.
  static PluginInstallRef? fromJson(Object? json) {
    final m = asMap(json);
    final repo = m == null ? null : readString(m, 'repo');
    final id = m == null ? null : readString(m, 'id');
    return repo == null || id == null
        ? null
        : PluginInstallRef(repo: repo, id: id);
  }

  /// URL of the repo index (`index.json`) the plugin manager reads.
  final String repo;

  /// Kartka plugin id (`mangayomi-<id>`).
  final String id;

  /// The JSON block.
  Map<String, Object?> toJson() => {'repo': repo, 'id': id};

  @override
  bool operator ==(Object other) =>
      other is PluginInstallRef && other.repo == repo && other.id == id;

  @override
  int get hashCode => Object.hash(repo, id);
}
