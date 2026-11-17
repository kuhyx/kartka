import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show ErrorSink;
import 'package:kartka/sync/rtdb_transport.dart';

/// The shared uploader's write (`kartka/errors` + `<device>/<id>` keys)
/// over kartka's [transport], whose paths are relative to `/kartka` (and
/// carry the sandbox namespace); null while signed out.
ErrorSink? errorSink(RtdbTransport? transport) => transport == null
    ? null
    : (path, values) => transport.patch({
        for (final MapEntry(:key, :value) in values.entries)
          '${path.replaceFirst(RegExp('^kartka/?'), '')}/$key': value,
      });
