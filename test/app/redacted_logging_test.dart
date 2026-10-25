import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/redacted_logging.dart';

const _leak = 'ClientException: x, uri=https://u:p@db.test/a.json?auth=SECRET';

void main() {
  late List<String?> printed;
  late DebugPrintCallback savedPrint;
  late ErrorCallback? savedOnError;

  setUp(() {
    printed = [];
    savedPrint = debugPrint;
    savedOnError = PlatformDispatcher.instance.onError;
    debugPrint = (m, {wrapWidth}) => printed.add(m);
    installRedactedLogging();
  });

  tearDown(() {
    debugPrint = savedPrint;
    PlatformDispatcher.instance.onError = savedOnError;
  });

  String all() => printed.join('\n');

  test('debugPrint (and so FlutterError dumps) never shows a token', () {
    debugPrint(_leak);
    FlutterError.dumpErrorToConsole(
      FlutterErrorDetails(exception: Exception(_leak)),
      forceReport: true,
    );
    expect(all(), isNot(contains('SECRET')));
    expect(all(), isNot(contains('u:p@')));
    expect(all(), contains('https://<redacted>@db.test/a.json?<redacted>'));
    debugPrint(null);
    expect(printed.last, isNull);
  });

  test('an uncaught error is printed redacted and marked handled', () {
    final handled = PlatformDispatcher.instance.onError!(
      Exception(_leak),
      StackTrace.fromString('#0 main (https://h.test/x.dart?k=V:1)'),
    );
    expect(handled, isTrue);
    expect(all(), contains('Unhandled error'));
    expect(all(), contains('db.test/a.json?<redacted>'));
    expect(all(), isNot(contains('SECRET')));
    expect(all(), isNot(contains('k=V')));
  });
}
