import 'package:flutter/widgets.dart';

/// Not available off the web: throws rather than pretending to sign in.
Future<void> gisInitialize(String clientId) =>
    throw UnsupportedError('Google Identity Services is web-only');

/// Not available off the web.
Widget gisButton() =>
    throw UnsupportedError('Google Identity Services is web-only');

/// Not available off the web.
Stream<String> gisIdTokens() =>
    throw UnsupportedError('Google Identity Services is web-only');
