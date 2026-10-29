import 'package:flutter/widgets.dart';
import 'package:kartka/core/models/manga.dart';
import 'package:kartka/core/models/manga_key.dart';

/// Port for extra actions on the manga detail screen (e.g. the tracking
/// button). Other parts register an implementation as a `KartkaFeature`
/// service; the detail screen renders every registered slot in its overflow
/// menu, in registry order. The menu builds its children only while open,
/// so work due when the screen opens belongs in [opened], not in a widget's
/// `initState`.
abstract interface class MangaDetailSlot {
  /// Called once when the detail screen for [key] opens.
  void opened(MangaKey key);

  /// Builds the slot's widget for the manga [key] with loaded [details].
  Widget build(BuildContext context, MangaKey key, MangaDetails details);
}
