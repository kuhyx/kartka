/// A [SourceHealthFeed] that re-scores, re-ranks and re-judges the base feed
/// with the active [ScoringProfile], live. The Sources tab and Browse's
/// badges both read it, so they follow the profile together.
library;

import 'dart:async';

import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/judge.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';

typedef _Snapshot = (List<SourceHealthRecord>, SourceHealthMeta?);

/// A base feed under the profile of a store.
///
/// Records the evaluator already judged with the active profile (its meta
/// says so; a run without one used DEFAULT) pass through untouched, so
/// under DEFAULT the published ranking is exactly what is shown. Otherwise
/// they are re-scored, and the meta's verdict totals are recounted. Records
/// and meta share one subscription to the base feed.
class ScoredHealthFeed implements SourceHealthFeed {
  /// Re-scores the base feed with the store's profile.
  new(this._base, this._store);

  final SourceHealthFeed _base;
  final ScoringProfileStore _store;
  late final Stream<_Snapshot> _shared = _join();

  @override
  Stream<List<SourceHealthRecord>> watch() => _shared.map((s) => s.$1);

  @override
  Stream<SourceHealthMeta?> watchMeta() => _shared.map((s) => s.$2);

  Stream<_Snapshot> _join() {
    final subs = <StreamSubscription<Object?>>[];
    List<SourceHealthRecord>? records;
    SourceHealthMeta? meta;
    var live = false;
    var profileKnown = false;
    late final StreamController<_Snapshot> out;

    void emit() {
      final r = records;
      if (!live || !profileKnown || r == null) return;
      out.add(_apply(r, meta, _store.profile.value));
    }

    void stop() {
      live = false;
      profileKnown = false;
      _store.profile.removeListener(emit);
      for (final s in subs) {
        unawaited(s.cancel());
      }
      subs.clear();
    }

    out = StreamController<_Snapshot>.broadcast(
      onListen: () {
        live = true;
        subs
          ..add(
            _base.watch().listen((r) {
              records = r;
              emit();
            }, onError: out.addError),
          )
          ..add(
            _base.watchMeta().listen((m) {
              meta = m;
              emit();
            }, onError: (Object _) {}),
          );
        // Wait for the stored profile, so DEFAULT never flashes.
        unawaited(
          _store.ready.then((_) {
            if (!live) return;
            profileKnown = true;
            _store.profile.addListener(emit);
            emit();
          }),
        );
      },
      onCancel: stop,
    );
    return out.stream;
  }

  _Snapshot _apply(
    List<SourceHealthRecord> records,
    SourceHealthMeta? meta,
    ScoringProfile profile,
  ) {
    final judged = meta?.profile ?? defaultScoringProfile;
    if (judged == profile) return (records, meta);
    final rescored = rescore(records, profile);
    return (rescored, meta?.withVerdicts(countVerdicts(rescored)));
  }
}
