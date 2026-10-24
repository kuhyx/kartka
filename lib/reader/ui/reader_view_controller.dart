/// Navigation a mounted reader view performs on request.
abstract interface class ReaderViewHandle {
  /// Moves [delta] pages (paged) or screens (webtoon); negative goes back.
  void step(int delta);

  /// Shows list item [item] at once.
  void jumpToItem(int item);
}

/// Lets the reader screen drive whichever view is mounted, so keys, taps
/// and the slider work the same in every mode.
class ReaderViewController {
  ReaderViewHandle? _handle;

  /// Called by a view when it mounts; returns the matching detach call.
  ///
  /// A view remounting under a new key replaces the old one, which then
  /// detaches harmlessly because [detach] checks identity.
  void Function() attach(ReaderViewHandle handle) {
    _handle = handle;
    return () => detach(handle);
  }

  /// Called by a view when it unmounts; ignores a stale handle.
  void detach(ReaderViewHandle handle) {
    if (identical(_handle, handle)) _handle = null;
  }

  /// Moves [delta] pages or screens, if a view is mounted.
  void step(int delta) => _handle?.step(delta);

  /// Shows item [item], if a view is mounted.
  void jumpToItem(int item) => _handle?.jumpToItem(item);
}
