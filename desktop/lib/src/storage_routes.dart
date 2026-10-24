import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/src/protocol.dart';
import 'package:path/path.dart' as p;

final _segment = RegExp(r'^[A-Za-z0-9._-]+$');
final _secretKey = RegExp(r'^[A-Za-z0-9._:-]+$');

/// Same rule as the app's `isValidBlobKey`.
bool isValidBlobKey(String key) =>
    key.isNotEmpty &&
    key.split('/').every((s) => s != '.' && s != '..' && _segment.hasMatch(s));

String _keyAfter(HttpRequest request, String root) =>
    Uri.decodeComponent(request.uri.path.substring(root.length + 1));

/// Writes [bytes] to [file] via a temp file and a rename, so a crash never
/// leaves half a page; the temp file gets [mode] before any byte is written.
Future<void> _atomicWrite(File file, List<int> bytes, {String? mode}) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsBytes(const []);
  if (mode != null) await Process.run('chmod', [mode, tmp.path]);
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(file.path);
}

/// `/files/<key>` (GET, PUT, DELETE) and `/files?prefix=` (JSON key list):
/// the web build's BlobStore, as real files under [root].
class FileRoutes {
  /// Stores under [root].
  new(this.root);

  /// Blob directory.
  final String root;

  /// Handles one request.
  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    if (request.uri.path == filesPath) {
      final prefix = request.uri.queryParameters['prefix'] ?? '';
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(await _list(prefix)));
      return;
    }
    final key = _keyAfter(request, filesPath);
    if (!isValidBlobKey(key)) {
      await request.drain<void>();
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    final file = File(p.joinAll([root, ...key.split('/')]));
    switch (request.method) {
      case 'PUT':
        final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        await _atomicWrite(file, bytes);
        response.statusCode = HttpStatus.noContent;
      case 'DELETE':
        if (file.existsSync()) await file.delete();
        response.statusCode = HttpStatus.noContent;
      case 'GET':
        if (!file.existsSync()) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        response.headers.contentType = ContentType.binary;
        await response.addStream(file.openRead());
      default:
        response.statusCode = HttpStatus.methodNotAllowed;
    }
  }

  Future<List<String>> _list(String prefix) async {
    final dir = Directory(root);
    if (!dir.existsSync()) return [];
    final keys = <String>[
      await for (final e in dir.list(recursive: true))
        if (e is File && !e.path.endsWith('.tmp'))
          p.split(p.relative(e.path, from: root)).join('/'),
    ];
    return keys.where((k) => k.startsWith(prefix)).toList()..sort();
  }
}

/// `/secrets/<key>` (GET, PUT, DELETE) and `/secrets?prefix=` (JSON map):
/// credentials in one JSON file kept at mode 0600 (directory 0700).
class SecretRoutes {
  /// Persists to [path].
  new(this.path);

  /// The secrets file, normally `~/.config/kartka/secrets.json`.
  final String path;

  Future<Map<String, String>> _load() async {
    final file = File(path);
    if (!file.existsSync()) return {};
    return (jsonDecode(await file.readAsString()) as Map<String, Object?>)
        .cast<String, String>();
  }

  Future<void> _save(Map<String, String> values) async {
    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
      await Process.run('chmod', ['700', dir.path]);
    }
    await _atomicWrite(
      File(path),
      utf8.encode(jsonEncode(values)),
      mode: '600',
    );
  }

  /// Handles one request.
  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    final values = await _load();
    if (request.uri.path == secretsPath) {
      final prefix = request.uri.queryParameters['prefix'] ?? '';
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          for (final e in values.entries)
            if (e.key.startsWith(prefix)) e.key: e.value,
        }),
      );
      return;
    }
    final key = _keyAfter(request, secretsPath);
    if (!_secretKey.hasMatch(key)) {
      await request.drain<void>();
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    switch (request.method) {
      case 'PUT':
        values[key] = await utf8.decodeStream(request);
        await _save(values);
        response.statusCode = HttpStatus.noContent;
      case 'DELETE':
        if (values.remove(key) != null) await _save(values);
        response.statusCode = HttpStatus.noContent;
      case 'GET':
        final value = values[key];
        if (value == null) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        response.headers.contentType = ContentType.text;
        response.write(value);
      default:
        response.statusCode = HttpStatus.methodNotAllowed;
    }
  }
}
