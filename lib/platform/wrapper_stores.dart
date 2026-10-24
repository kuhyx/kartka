import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/wrapper_protocol.dart';

/// The wrapper answered an API call with an unexpected status.
class WrapperException implements Exception {
  /// Creates the exception for [method] [path] answering [statusCode].
  const new(this.method, this.path, this.statusCode);

  /// Request method.
  final String method;

  /// Request path.
  final String path;

  /// The unexpected status.
  final int statusCode;

  @override
  String toString() => 'WrapperException($method $path -> $statusCode)';
}

/// Shared plumbing for the wrapper-backed stores.
abstract class _WrapperRoute {
  new(this.client, this.base, this.root);

  final http.Client client;
  final Uri base;
  final String root;

  Uri _uri(String key) => base.replace(path: '$root/$key');

  Uri _listUri(String prefix) =>
      base.replace(path: root, queryParameters: {'prefix': prefix});

  Future<http.Response> _call(
    String method,
    Uri uri, {
    List<int>? body,
    bool allowMissing = false,
  }) async {
    final request = http.Request(method, uri)
      ..headers[KartkaWrapper.apiHeader] = '1';
    if (body != null) request.bodyBytes = body;
    final response = await http.Response.fromStream(await client.send(request));
    final status = response.statusCode;
    if (status ~/ 100 == 2 || (allowMissing && status == 404)) return response;
    throw WrapperException(method, uri.path, status);
  }
}

/// [BlobStore] on the wrapper's `/files/` routes (web build): pages land as
/// real files on disk, beyond the reach of a wiped browser profile.
class WrapperBlobStore extends _WrapperRoute implements BlobStore {
  /// Talks to the wrapper at [base] through [client].
  new(http.Client client, Uri base)
    : super(client, base, KartkaWrapper.filesPath);

  @override
  Future<void> put(String key, Uint8List bytes) async {
    checkBlobKey(key);
    await _call('PUT', _uri(key), body: bytes);
  }

  @override
  Future<Uint8List?> get(String key) async {
    checkBlobKey(key);
    final r = await _call('GET', _uri(key), allowMissing: true);
    return r.statusCode == 404 ? null : r.bodyBytes;
  }

  @override
  Future<void> delete(String key) async {
    checkBlobKey(key);
    await _call('DELETE', _uri(key), allowMissing: true);
  }

  @override
  Future<List<String>> list(String prefix) async {
    final r = await _call('GET', _listUri(prefix));
    return (jsonDecode(r.body) as List<Object?>).cast<String>();
  }
}

final _secretKey = RegExp(r'^[A-Za-z0-9._:-]+$');

/// [KeyValueStore] on the wrapper's `/secrets/` routes (web build): a 0600
/// file in `~/.config/kartka/`, never browser storage.
class WrapperKeyValueStore extends _WrapperRoute implements KeyValueStore {
  /// Talks to the wrapper at [base] through [client].
  new(http.Client client, Uri base)
    : super(client, base, KartkaWrapper.secretsPath);

  static String _checked(String key) {
    if (!_secretKey.hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'use [A-Za-z0-9._:-]');
    }
    return key;
  }

  @override
  Future<String?> get(String key) async {
    final r = await _call('GET', _uri(_checked(key)), allowMissing: true);
    return r.statusCode == 404 ? null : utf8.decode(r.bodyBytes);
  }

  @override
  Future<void> set(String key, String value) async =>
      await _call('PUT', _uri(_checked(key)), body: utf8.encode(value));

  @override
  Future<void> remove(String key) async =>
      await _call('DELETE', _uri(_checked(key)), allowMissing: true);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async {
    final r = await _call('GET', _listUri(prefix));
    return (jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>)
        .cast<String, String>();
  }
}
