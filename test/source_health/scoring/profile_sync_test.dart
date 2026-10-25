// The scoring profile rides the existing settings sync: same node on every
// device, a JSON string under `value`, which is what the evaluator reads.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/sync/rtdb_transport.dart';

import '../../sync/fakes.dart';
import '../../sync/settings/settings_harness.dart';

void main() {
  test(
    'a profile saved on one device reaches the other and the node',
    () async {
      final db = InMemoryRtdb();
      final clock = TestClock();
      final a = await SettingsDevice.create('dev-a', db, clock: clock);
      final b = await SettingsDevice.create('dev-b', db, clock: clock);
      final storeA = ScoringProfileStore(a.kv);
      final storeB = ScoringProfileStore(b.kv);
      await Future.wait([storeA.ready, storeB.ready]);
      final custom = defaultScoringProfile.copyWith(
        keepScore: 0.5,
        cuts: {HealthReason.subset},
      );

      await storeA.save(custom);
      await a.settle();
      await b.poll();
      await pumpEventQueue();
      expect(storeB.profile.value, custom);

      final node =
          (db.tree['settings']! as Map)[rtdbKey(kScoringSetting)]! as Map;
      expect(node['key'], kScoringSetting);
      expect(jsonDecode(node['value']! as String), custom.toJson());

      // Reset on B removes the value everywhere: DEFAULT again on A.
      clock.advance();
      await storeB.reset();
      await b.settle();
      await a.poll();
      await pumpEventQueue();
      expect(storeA.profile.value, defaultScoringProfile);
    },
  );
}
