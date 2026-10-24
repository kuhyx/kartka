import 'package:kartka/core/models/manga_key.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/tracking/common/binding_store.dart';

/// Library's [TrackedLookup] port, answered from the binding store.
class BindingTrackedLookup implements TrackedLookup {
  /// Creates the lookup over [_store].
  const new(this._store);

  final BindingStore _store;

  @override
  Stream<bool> isTracked(MangaKey key) =>
      _store.watch(key).map((bindings) => bindings.isNotEmpty).distinct();
}
