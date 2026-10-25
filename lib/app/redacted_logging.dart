/// Console output (logcat on Android, the browser console on web) never
/// shows a URL secret: Firebase ID tokens ride in RTDB URLs (`?auth=`),
/// and a ClientException prints its whole URL.
library;

import 'package:flutter/foundation.dart';
import 'package:kartka/core/redact.dart';

/// Wraps [debugPrint] with [redactUrlQueries] and prints uncaught errors
/// through it. Called once from `main`.
///
/// One wrap covers the framework too: `FlutterError.presentError` dumps via
/// `debugPrint` (`debugPrintStack` in release). Uncaught async errors would
/// otherwise reach the engine's "Unhandled Exception" print unredacted, so
/// [PlatformDispatcher.onError] prints them itself and reports them handled.
void installRedactedLogging() {
  final inner = debugPrint;
  debugPrint = (message, {wrapWidth}) => inner(
    message == null ? null : redactUrlQueries(message),
    wrapWidth: wrapWidth,
  );
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    return true;
  };
}
