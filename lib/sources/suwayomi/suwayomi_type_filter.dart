import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_queries.dart';

/// One `FilterChangeInput` of Suwayomi's `fetchSourceManga`.
typedef FilterChange = Map<String, Object?>;

enum _Kind { manga, manhwa, manhua, other }

/// What a Suwayomi source's filter list (`source { filters }`, fetched with
/// `SuwayomiQueries.sourceFilters`) offers for [ContentType]s.
///
/// The type filter is the first group or select named like "type" or
/// "original language" with an option naming manga (manhwa / manhua
/// options are told apart by name; any other option, e.g. "Other", counts
/// as manga). A select holds one choice, so it can express one ticked type
/// but not two. The sort filter is the
/// first `SortFilter`, or a select named like "sort" / "order"; Popular
/// picks its first option like popular / view / trend / follow, Latest its
/// first like latest / update / upload. Positions count every element of
/// the list, separators and headers included (docs/DOCS-suwayomi.md).
class SuwayomiTypeFilter {
  const new _(this._type, this._popular, this._latest);

  /// Reads a `KartkaSourceFilters` response body.
  factory fromResponse(Map<String, Object?> body) {
    final data = body['data']! as Map<String, Object?>;
    final source = data['source']! as Map<String, Object?>;
    return SuwayomiTypeFilter.parse(source['filters']! as List<Object?>);
  }

  /// Reads a source's filter list.
  factory parse(List<Object?> filters) {
    final list = [for (final f in filters) f! as Map<String, Object?>];
    _TypeFilter? type;
    FilterChange? Function(RegExp)? sort;
    for (final (i, f) in list.indexed) {
      type ??= _TypeFilter.at(i, f);
      sort ??= _sortAt(i, f);
    }
    return SuwayomiTypeFilter._(
      type,
      sort?.call(RegExp('popular|view|trend|follow', caseSensitive: false)),
      sort?.call(RegExp('latest|update|upload', caseSensitive: false)),
    );
  }

  final _TypeFilter? _type;
  final FilterChange? _popular;
  final FilterChange? _latest;

  /// Reads the filter list of source [serverId] through [client].
  static Future<SuwayomiTypeFilter> fetch(
    SuwayomiClient client,
    String serverId,
  ) async => SuwayomiTypeFilter.fromResponse({
    'data': await client.run(SuwayomiQueries.sourceFilters, {'id': serverId}),
  });

  /// The filters that narrow [listing] to [types]; null when this source
  /// cannot (no type filter, or no sort option for Popular / Latest) and
  /// for [ContentTypes.all] / [ContentTypes.none], which send none.
  List<FilterChange>? changesFor(Listing listing, ContentTypes types) {
    if (types.isAll || types.isNone) return null;
    final allowed = {
      for (final t in types.ticked)
        ...switch (t) {
          ContentType.manga => const [_Kind.manga, _Kind.other],
          ContentType.manhwa => const [_Kind.manhwa],
          ContentType.manhua => const [_Kind.manhua],
        },
    };
    final narrowed = _type?.changes(allowed);
    if (narrowed == null) return null;
    return switch ((listing, _popular, _latest)) {
      (Listing.search, _, _) => narrowed,
      (Listing.popular, final sort?, _) => [...narrowed, sort],
      (Listing.latest, _, final sort?) => [...narrowed, sort],
      _ => null,
    };
  }

  static final _sortName = RegExp('sort|order', caseSensitive: false);

  static FilterChange? Function(RegExp)? _sortAt(
    int i,
    Map<String, Object?> f,
  ) {
    final typename = f['__typename'];
    final isSelect =
        typename == 'SelectFilter' && _sortName.hasMatch('${f['name']}');
    if (typename != 'SortFilter' && !isSelect) return null;
    final values = (f['values']! as List<Object?>).cast<String>();
    return (wanted) {
      final index = values.indexWhere(wanted.hasMatch);
      if (index < 0) return null;
      return isSelect
          ? {'position': i, 'selectState': index}
          : {
              'position': i,
              'sortState': {'index': index, 'ascending': false},
            };
    };
  }
}

class _TypeFilter {
  const new(this.position, this.kinds, {required this.isGroup});

  static final _name = RegExp('type|original language', caseSensitive: false);

  static _TypeFilter? at(int i, Map<String, Object?> f) {
    if (!_name.hasMatch('${f['name']}')) return null;
    final _TypeFilter filter;
    switch (f['__typename']) {
      case 'GroupFilter':
        final children = [
          for (final c in f['filters']! as List<Object?>)
            c! as Map<String, Object?>,
        ];
        filter = _TypeFilter(i, [
          for (final c in children)
            switch (c['__typename']) {
              'CheckBoxFilter' => (_kindOf('${c['name']}'), 'checkBoxState'),
              'TriStateFilter' => (_kindOf('${c['name']}'), 'triState'),
              _ => null,
            },
        ], isGroup: true);
      case 'SelectFilter':
        filter = _TypeFilter(i, [
          for (final v in f['values']! as List<Object?>)
            (_kindOf('$v'), 'selectState'),
        ], isGroup: false);
      default:
        return null;
    }
    return filter.kinds.any((k) => k?.$1 == _Kind.manga) ? filter : null;
  }

  static _Kind _kindOf(String name) {
    final n = name.toLowerCase();
    if (n.contains('manhwa')) return _Kind.manhwa;
    if (n.contains('manhua')) return _Kind.manhua;
    return n.contains('manga') ? _Kind.manga : _Kind.other;
  }

  final int position;

  /// One entry per group child or select option: its kind and the
  /// `FilterChangeInput` field that sets it (null: not a toggle).
  final List<(_Kind, String)?> kinds;
  final bool isGroup;

  List<FilterChange>? changes(Set<_Kind> allowed) {
    if (!isGroup) {
      final named = allowed.difference(const {_Kind.other});
      if (named.length != 1) return null;
      final index = kinds.indexWhere((k) => k!.$1 == named.single);
      if (index < 0) return null;
      return [
        {'position': position, 'selectState': index},
      ];
    }
    return [
      for (final (j, k) in kinds.indexed)
        if (k case (final kind, final field))
          {
            'position': position,
            'groupChange': {
              'position': j,
              field: field == 'triState'
                  ? (allowed.contains(kind) ? 'INCLUDE' : 'IGNORE')
                  : allowed.contains(kind),
            },
          },
    ];
  }
}

/// One source's [SuwayomiTypeFilter], read on first use. A failed read is
/// not kept: that listing goes unfiltered and the next one reads again.
class TypeFilterCache {
  /// Creates the cache for source [serverId] on [client]'s server.
  new(this.client, this.serverId);

  /// GraphQL client.
  final SuwayomiClient client;

  /// Server-side source id.
  final String serverId;

  Future<SuwayomiTypeFilter>? _filter;

  /// [SuwayomiTypeFilter.changesFor], null as well when the read failed.
  Future<List<FilterChange>?> changesFor(Listing listing, ContentTypes types) {
    final filter = _filter ??= SuwayomiTypeFilter.fetch(client, serverId);
    return filter.then(
      (f) => f.changesFor(listing, types),
      onError: (Object _) => _filter = null,
    );
  }
}
