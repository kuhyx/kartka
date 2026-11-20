/// Watches the page images a chapter opens on (971debc8): when every one
/// of them failed and none loaded, the reader showed only broken-image
/// icons and nothing said why. The callback then runs once, with the last
/// error, so the cause goes up as a report.
class FirstImagesProbe {
  /// Watches the pages at [watched] (flat indexes).
  new(Iterable<int> watched, this._onAllFailed) : _left = Set.of(watched);

  final Set<int> _left;
  final void Function(Object error) _onAllFailed;
  bool _done = false;

  /// [load] of the page at [index], unchanged; its outcome is counted.
  Future<T> watch<T>(int index, Future<T> load) => load.then(
    (value) {
      if (_left.contains(index)) _done = true;
      return value;
    },
    onError: (Object e, StackTrace stack) {
      if (!_done && _left.remove(index) && _left.isEmpty) {
        _done = true;
        _onAllFailed(e);
      }
      return Future<T>.error(e, stack);
    },
  );
}
