import 'dart:convert';
import 'dart:typed_data';

import 'package:kartka/platform/file_picker.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/oauth_redirect.dart';

/// One request seen by [FakeKartkaHttp].
typedef FakeRequest = ({
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
});

/// [KartkaHttp] answering from a handler and recording every request.
///
/// For unit tests of sources and trackers: pair it with recorded fixtures in
/// `test/fixtures/<source>/` (no live network in unit tests).
class FakeKartkaHttp extends KartkaHttp {
  /// Answers with [handler]; the default answers 404 to everything.
  new([KartkaResponse Function(FakeRequest request)? handler])
    : _handler = handler ?? ((_) => text('', status: 404));

  final KartkaResponse Function(FakeRequest request) _handler;

  /// Every request so far, in order.
  final List<FakeRequest> requests = [];

  /// A UTF-8 text response.
  static KartkaResponse text(
    String body, {
    int status = 200,
    Map<String, String> headers = const {},
  }) => KartkaResponse(
    statusCode: status,
    bodyBytes: Uint8List.fromList(utf8.encode(body)),
    headers: headers,
  );

  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    checkHttpMethod(method);
    final request = (method: method, url: url, headers: headers, body: body);
    requests.add(request);
    return _handler(request);
  }
}

/// [FilePicker] returning canned files.
class FakeFilePicker implements FilePicker {
  /// Returns [files] from [pickFiles] and [directory] from [pickDirectory].
  new({this.files = const [], this.directory = const []});

  /// What [pickFiles] returns.
  final List<PickedFile> files;

  /// What [pickDirectory] returns.
  final List<PickedFile> directory;

  /// The extensions of the last [pickFiles] call.
  List<String>? lastExtensions;

  @override
  Future<List<PickedFile>> pickFiles({
    List<String> extensions = const [],
    bool multiple = false,
  }) async {
    lastExtensions = extensions;
    return files;
  }

  @override
  Future<List<PickedFile>> pickDirectory() async => directory;
}

/// [OAuthRedirect] that answers each authorization with a callback.
class FakeOAuthRedirect implements OAuthRedirect {
  /// Creates the fake for [redirectUri] (default `kartka://oauth`; pass
  /// `http://127.0.0.1:47391/oauth` to test the web flow). The default
  /// response echoes the bare redirect URI.
  new([Uri Function(Uri authorizationUrl)? respond, Uri? redirectUri])
    : redirectUri = redirectUri ?? Uri.parse('kartka://oauth'),
      _respond = respond;

  final Uri Function(Uri authorizationUrl)? _respond;

  /// Every authorization URL opened, in order.
  final List<Uri> authorized = [];

  @override
  final Uri redirectUri;

  @override
  Future<Uri> authorize(
    Uri authorizationUrl, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    authorized.add(authorizationUrl);
    return _respond?.call(authorizationUrl) ?? redirectUri;
  }
}
