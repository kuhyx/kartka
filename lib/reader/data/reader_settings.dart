import 'package:flutter/foundation.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/logic/tap_zones.dart';

/// Global reader preferences. The per-manga mode override lives separately
/// in `ReaderPrefs`, so changing one manga never touches these.
@immutable
class ReaderSettings {
  /// Creates settings; [prefetchAhead] is expected in `0..maxPrefetch`.
  const new({
    this.defaultMode = ReaderMode.pagedRtl,
    this.prefetchAhead = 3,
    this.tapLayout = TapZoneLayout.thirds,
    this.invertTaps = false,
  });

  /// Reads settings, falling back to defaults for any bad field.
  factory fromJson(Map<String, Object?> json) {
    const d = ReaderSettings();
    final prefetch = json['prefetchAhead'];
    final invert = json['invertTaps'];
    final layout = json['tapLayout'];
    final mode = json['defaultMode'];
    return ReaderSettings(
      defaultMode:
          ReaderMode.fromId(mode is String ? mode : null) ?? d.defaultMode,
      prefetchAhead: prefetch is int
          ? _clampPrefetch(prefetch)
          : d.prefetchAhead,
      tapLayout:
          TapZoneLayout.fromId(layout is String ? layout : null) ?? d.tapLayout,
      invertTaps: invert is bool ? invert : d.invertTaps,
    );
  }

  /// Upper bound for [prefetchAhead]; more only burns memory and bandwidth.
  static const int maxPrefetch = 10;

  /// Mode used for manga without their own override.
  final ReaderMode defaultMode;

  /// How many pages after the current one are fetched in advance.
  final int prefetchAhead;

  /// Which tap regions navigate.
  final TapZoneLayout tapLayout;

  /// Whether previous/next tap regions are swapped.
  final bool invertTaps;

  static int _clampPrefetch(int n) => n.clamp(0, maxPrefetch);

  /// A copy with the given fields replaced.
  ReaderSettings copyWith({
    ReaderMode? defaultMode,
    int? prefetchAhead,
    TapZoneLayout? tapLayout,
    bool? invertTaps,
  }) => ReaderSettings(
    defaultMode: defaultMode ?? this.defaultMode,
    prefetchAhead: _clampPrefetch(prefetchAhead ?? this.prefetchAhead),
    tapLayout: tapLayout ?? this.tapLayout,
    invertTaps: invertTaps ?? this.invertTaps,
  );

  /// JSON form stored in the key-value store.
  Map<String, Object?> toJson() => {
    'defaultMode': defaultMode.id,
    'prefetchAhead': prefetchAhead,
    'tapLayout': tapLayout.id,
    'invertTaps': invertTaps,
  };

  @override
  bool operator ==(Object other) =>
      other is ReaderSettings &&
      other.defaultMode == defaultMode &&
      other.prefetchAhead == prefetchAhead &&
      other.tapLayout == tapLayout &&
      other.invertTaps == invertTaps;

  @override
  int get hashCode =>
      Object.hash(defaultMode, prefetchAhead, tapLayout, invertTaps);
}
