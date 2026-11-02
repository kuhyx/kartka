import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android APK must not link Google's proprietary sign-in libraries
/// (googleid / play-services-auth). Android signs in through
/// crdt_sync_flutter's google_account_token plugin (AccountManager); the web
/// build keeps the GIS button via google_sign_in_web, which has no Android
/// half. The app-facing `google_sign_in` package would bring
/// google_sign_in_android back, so it must not reappear in the lockfile.
void main() {
  final lock = File('pubspec.lock').readAsStringSync();

  for (final package in [
    'google_sign_in',
    'google_sign_in_android',
    'google_sign_in_ios',
  ]) {
    test('$package is not in the lockfile', () {
      expect(lock, isNot(contains('\n  $package:\n')));
    });
  }

  test('the web-only GIS packages and the Android plugin are', () {
    expect(lock, contains('\n  google_sign_in_web:\n'));
    expect(lock, contains('\n  google_account_token:\n'));
  });
}
