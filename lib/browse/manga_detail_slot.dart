import 'package:flutter/widgets.dart';
import 'package:kartka/core/models/manga.dart';
import 'package:kartka/core/models/manga_key.dart';

/// Port for extra actions on the manga detail screen (e.g. the tracking
/// button). Other parts register an implementation as a `KartkaFeature`
/// service; the detail screen renders every registered slot in its action
/// row, in registry order.
// One-method port by design: registry lookup is by type, so a typedef
// would not be distinguishable from any other function service.
// ignore: one_member_abstracts
abstract interface class MangaDetailSlot {
  /// Builds the slot's widget for the manga [key] with loaded [details].
  Widget build(BuildContext context, MangaKey key, MangaDetails details);
}
