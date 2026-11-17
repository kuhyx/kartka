import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:kartka/platform/wrapper_protocol.dart';

/// Whether this web build is served by the headless agent wrapper
/// (`--agent`, tools/agent): its checks must not file board tickets, so
/// the error upload stays off. Android, kuhy's own wrapper, an older
/// wrapper (no such route) and any failure all answer false.
Future<bool> isAgentInstance({
  bool isWeb = kIsWeb,
  Uri? base,
  http.Client? client,
}) async {
  if (!isWeb) return false;
  final here = base ?? Uri.base;
  final http.Response reply;
  try {
    reply = await (client ?? http.Client()).get(
      Uri(
        scheme: here.scheme,
        host: here.host,
        port: here.port,
        path: KartkaWrapper.agentPath,
      ),
      headers: {KartkaWrapper.apiHeader: '1'},
    );
    final json = jsonDecode(reply.body);
    return json is Map && json['agent'] == true;
  } on Object {
    return false;
  }
}
