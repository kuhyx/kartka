import 'package:glados/glados.dart';
import 'package:kartka/sync/rtdb_transport.dart';

import '../fakes.dart';
import 'settings_harness.dart';

/// One step: device 0 or 1 either polls (value null) or saves a value, to
/// the plain URL or the encrypted password.
typedef _Op = ({int device, bool secret, String? value});

extension on Any {
  Generator<_Op> get op => combine3(
    intInRange(0, 2),
    this.bool,
    choose<String?>([null, 'a', 'b', 'c']),
    (device, secret, value) => (device: device, secret: secret, value: value),
  );
}

const _url = 'suwayomi.serverUrl';
const _pass = 'suwayomi.password';

void main() {
  Glados(any.listWithLengthInRange(1, 8, any.op)).test(
    'per-key LWW: any interleaving converges on the newest change',
    (ops) async {
      final db = InMemoryRtdb();
      final clock = TestClock();
      final devices = [
        await SettingsDevice.create('dev-a', db, clock: clock),
        await SettingsDevice.create('dev-b', db, clock: clock),
      ];
      // The model: a save is a change only if it differs from what the
      // saving device last knew (its merged view), exactly like an
      // untouched form field. The newest change must win everywhere.
      final winner = <bool, String>{};
      final known = [<bool, String>{}, <bool, String>{}];
      for (final o in ops) {
        clock.advance();
        final d = devices[o.device];
        final value = o.value;
        if (value == null) {
          await d.poll();
          known[o.device] = {...winner};
          continue;
        }
        await (o.secret ? d.secrets.set(_pass, value) : d.kv.set(_url, value));
        await d.settle();
        if (known[o.device][o.secret] != value) {
          winner[o.secret] = known[o.device][o.secret] = value;
        }
      }
      for (var round = 0; round < 2; round++) {
        for (final d in devices) {
          await d.poll();
        }
      }
      for (final d in devices) {
        expect(await d.local.get(_url), winner[false]);
        expect(await d.secretsLocal.get(_pass), winner[true]);
      }
    },
  );
}
