import 'dart:io';

import 'package:kartka_desktop/kartka_desktop.dart';
import 'package:test/test.dart';

void main() {
  test(
    'mirrors the app wrapper protocol (lib/platform/wrapper_protocol.dart)',
    () {
      final app = File('../lib/platform/wrapper_protocol.dart')
          .readAsStringSync();
      expect(app, contains('const kartkaWrapperPort = $kartkaPort;'));
      for (final value in [
        apiHeader,
        requestHeaderPrefix,
        responseHeaderPrefix,
        proxyPath,
        filesPath,
        secretsPath,
        oauthPath,
        oauthResultPath,
        syncCredentialsPath,
        enginePath,
      ]) {
        expect(app, contains("'$value'"), reason: value);
      }
      final ua = File('../lib/platform/http_client.dart').readAsStringSync();
      expect(ua, contains("'$kartkaUserAgent'"));
    },
  );
}
