import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kartka/browse/manga_detail_slot.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/tracking/common/tracking_service.dart';
import 'package:kartka/tracking/common/ui/track_button.dart';

/// Browse's [MangaDetailSlot]: the track button on the manga detail screen.
class TrackingDetailSlot implements MangaDetailSlot {
  /// Creates the slot over [_service].
  const new(this._service);

  final TrackingService _service;

  /// Pulls remote progress forward once per detail-screen open.
  @override
  void opened(MangaKey key) => unawaited(_service.refresh(key));

  @override
  Widget build(BuildContext context, MangaKey key, MangaDetails details) =>
      TrackButton(service: _service, mangaKey: key, title: details.title);
}
