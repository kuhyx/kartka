/// The page the reader shows, as background work on sources sees it
/// (28fffd0a). A source serves a few pages a second, and a download or a
/// next chapter's page list beside the shown page put that page behind
/// them. The reader registers one as a service; other parts find it with
/// `registry.all<ShownPageGate>()` and never import the reader.
abstract interface class ShownPageGate {
  /// Completes once no shown page is loading (at once when none is), or
  /// after a cap, so a stuck page never stalls the work behind it.
  Future<void> idle();
}
