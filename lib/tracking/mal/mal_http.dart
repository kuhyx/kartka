/// Adapts `KartkaHttp` (the only HTTP client, contracts §2) to [MalSend].
library;

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

/// The HTTP method name `KartkaHttp.send` expects for [method].
String malMethodName(MalMethod method) => method.name.toUpperCase();

/// A [MalSend] that sends every request through [http].
MalSend malSendVia(KartkaHttp http) => (request) async {
  final res = await http.send(
    malMethodName(request.method),
    request.url,
    headers: request.headers,
    body: request.body,
  );
  return MalResponse(res.statusCode, res.body);
};
