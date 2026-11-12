import 'package:crdt_sync/crdt_sync.dart' show Argon2Params, E2eCipher, E2eKey;
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show kE2ePassphraseKey;
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/e2e/e2e_unlock.dart';

/// Argon2id cheap enough for unit tests.
const Argon2Params kTestArgon = Argon2Params(
  memoryKiB: 8,
  iterations: 1,
  parallelism: 1,
);

/// The passphrase every test device shares.
const String kTestPassphrase = 'test-passphrase';

/// A [KartkaE2e] over in-memory secrets holding [passphrase] (none: null).
KartkaE2e testE2e({String? passphrase = kTestPassphrase}) => KartkaE2e(
  MemoryKeyValueStore({kE2ePassphraseKey: ?passphrase}),
  params: kTestArgon,
);

/// A cipher over fixed key bytes [fill], as the app builds it.
Future<E2eCipher> testCipher([int fill = 7]) async =>
    (await E2eKey.fromBytes(List.filled(32, fill)))
        .cipher(acceptPlaintext: false);
