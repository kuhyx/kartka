/// No registered source has [sourceId]: a plugin that was uninstalled, or a
/// Suwayomi source its server no longer lists. A [StateError] so existing
/// handlers (and the `Bad state: Unknown source ...` text) are unchanged;
/// the update runner tells it apart to skip the source instead of failing
/// every one of its manga.
class UnknownSourceError extends StateError {
  /// Creates the error for [sourceId].
  new(this.sourceId) : super('Unknown source $sourceId');

  /// The id nothing is registered under.
  final String sourceId;
}
