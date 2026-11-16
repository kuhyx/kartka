/// The active scoring profile: one synced setting (DOCS-contracts-runtime §16),
/// so it is the same on every device and the evaluator reads it too.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/source_health/scoring/profile.dart';

/// The settings key; node `/kartka/settings/sourceHealth~2Escoring`. Listed
/// in `lib/sync/settings/settings_catalog.dart` (plain vault) and shared with
/// the evaluator through `scoring_profile.json`.
const String kScoringSetting = 'sourceHealth.scoring';

/// Holds the active [ScoringProfile] and persists edits through the synced
/// store. The value is the DEFAULT until the first read of the store ends
/// ([ready]); a missing or invalid stored profile also reads as DEFAULT.
class ScoringProfileStore {
  /// Reads the stored profile now and again when a peer replaces it.
  new(this._kv) {
    ready = _load();
    unawaited(
      _kv.remoteChanges
          .where((key) => key == kScoringSetting)
          .forEach((_) => _load()),
    );
  }

  final SyncedKeyValueStore _kv;

  /// The active profile; listen to re-score live.
  final ValueNotifier<ScoringProfile> profile = ValueNotifier(
    defaultScoringProfile,
  );

  /// Completes once the stored profile has been read.
  late final Future<void> ready;

  Future<void> _load() async {
    final raw = await _kv.get(kScoringSetting);
    var read = defaultScoringProfile;
    if (raw != null) {
      try {
        read = ScoringProfile.fromJson(jsonDecode(raw)) ?? read;
      } on FormatException {
        // Hand-edited: score with DEFAULT, as the evaluator does.
      }
    }
    profile.value = read;
  }

  /// Shows [p] right away without storing it (a slider mid-drag).
  void preview(ScoringProfile p) {
    if (p != profile.value) profile.value = p;
  }

  /// Makes [p] the active profile and stores it (DEFAULT removes the
  /// setting). A profile with all weights 0 is invalid and ignored.
  Future<void> save(ScoringProfile p) async {
    if (p.weights.total <= 0) return;
    profile.value = p;
    if (p.isDefault) {
      await _kv.remove(kScoringSetting);
    } else {
      await _kv.set(kScoringSetting, jsonEncode(p.toJson()));
    }
  }

  /// Restores [defaultScoringProfile].
  Future<void> reset() => save(defaultScoringProfile);
}
