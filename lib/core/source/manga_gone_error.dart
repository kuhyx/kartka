/// The source (or its server) no longer has this manga: a known state the
/// screens show, never a report. Sources throw an error implementing it;
/// the update runner and the details screen test for it without importing
/// any source.
abstract interface class MangaGoneError implements Exception;
