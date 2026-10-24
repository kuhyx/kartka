import 'package:collection/collection.dart';

/// MangaDex content ratings, in the API's own spelling (`name`).
enum ContentRating {
  /// All ages.
  safe('Safe'),

  /// Mild fan service.
  suggestive('Suggestive'),

  /// Explicit, non-pornographic.
  erotica('Erotica'),

  /// Pornographic.
  pornographic('Pornographic');

  new(this.label);

  /// Label shown in the settings tile.
  final String label;
}

const _list = ListEquality<String>();
const _set = SetEquality<ContentRating>();

/// User settings of the MangaDex source, stored as JSON in KeyValueStore.
class MangadexSettings {
  /// Creates settings; [languages] and [ratings] must not be empty.
  const new({
    required this.languages,
    required this.dataSaver,
    required this.ratings,
  });

  /// Decodes [toJson]; absent, empty or unknown values fall back to defaults.
  factory fromJson(Map<String, Object?> json) {
    final langs = (json['languages'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toList();
    final names = (json['ratings'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toSet();
    final ratings = {
      for (final r in ContentRating.values)
        if (names.contains(r.name)) r,
    };
    return MangadexSettings(
      languages: langs.isEmpty ? defaults.languages : List.unmodifiable(langs),
      dataSaver: json['dataSaver'] as bool? ?? defaults.dataSaver,
      ratings: ratings.isEmpty ? defaults.ratings : Set.unmodifiable(ratings),
    );
  }

  /// English, full-quality images, safe + suggestive.
  static const defaults = MangadexSettings(
    languages: ['en'],
    dataSaver: false,
    ratings: {ContentRating.safe, ContentRating.suggestive},
  );

  /// Chapter languages (ISO 639-1 as MangaDex spells them, e.g. `pt-br`),
  /// in preference order; the first also picks titles and descriptions.
  final List<String> languages;

  /// Whether pages come from MangaDex's compressed `data-saver` set.
  final bool dataSaver;

  /// Content ratings shown when browsing and searching.
  final Set<ContentRating> ratings;

  /// Copy with the given fields replaced.
  MangadexSettings copyWith({
    List<String>? languages,
    bool? dataSaver,
    Set<ContentRating>? ratings,
  }) => MangadexSettings(
    languages: languages ?? this.languages,
    dataSaver: dataSaver ?? this.dataSaver,
    ratings: ratings ?? this.ratings,
  );

  /// Ratings in the API's canonical order.
  List<String> get ratingNames => [
    for (final r in ContentRating.values)
      if (ratings.contains(r)) r.name,
  ];

  /// JSON shape read by [MangadexSettings.fromJson].
  Map<String, Object?> toJson() => {
    'languages': languages,
    'dataSaver': dataSaver,
    'ratings': ratingNames,
  };

  @override
  bool operator ==(Object other) =>
      other is MangadexSettings &&
      _list.equals(other.languages, languages) &&
      other.dataSaver == dataSaver &&
      _set.equals(other.ratings, ratings);

  @override
  int get hashCode =>
      Object.hash(_list.hash(languages), dataSaver, _set.hash(ratings));
}
