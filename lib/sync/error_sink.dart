import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show AppErrors, ErrorSink, ErrorUploader;
import 'package:kartka/platform/agent_probe.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_runtime.dart';

/// The shared uploader's write (`kartka/errors` + `<device>/<id>` keys)
/// over kartka's [transport], whose paths are relative to `/kartka` (and
/// carry the sandbox namespace); null while signed out.
ErrorSink? errorSink(RtdbTransport? transport) => transport == null
    ? null
    : (path, values) => transport.patch({
        for (final MapEntry(:key, :value) in values.entries)
          '${path.replaceFirst(RegExp('^kartka/?'), '')}/$key': value,
      });

/// Starts [errors]' upload over [runtime]'s signed-in transport as its
/// device (never starts sync); nothing before `installAppErrors` (tests).
/// In the headless agent instance ([isAgent]) the sink stays null, so its
/// checks queue reports on the device but never file board tickets.
ErrorUploader? connectErrorUploads(
  AppErrors? errors,
  SyncRuntime runtime, {
  Future<bool> Function() isAgent = isAgentInstance,
}) {
  if (errors == null) return null;
  final agent = isAgent();
  return errors.connect(
    sink: () async => await agent ? null : errorSink(await runtime.transport()),
    deviceId: runtime.deviceId,
  );
}
