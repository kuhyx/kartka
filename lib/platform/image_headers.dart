/// Extra request headers for image URLs (cover art and pages).
///
/// Sources whose image hosts need e.g. a `Referer` provide one through
/// `KartkaFeature.services`; `PageImageLoader` merges every registered
/// provider, then the `PageRef`'s own headers win.
abstract interface class ImageHeaders {
  /// Headers to send when fetching [url]; empty when this provider does not
  /// recognise the host.
  Map<String, String> forUrl(String url);
}
