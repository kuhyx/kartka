import 'dart:typed_data';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/platform/plugin_file_picker.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

final class _File extends PlatformFile {
  new(this.name, this.bytes);
  @override
  final String name;
  final List<int> bytes;
  @override
  Uri get uri => Uri.parse('memory:$name');
  // xFile is never read by PluginFilePicker; noSuchMethod covers it without
  // naming cross_file's XFile (a transitive pin this repo cannot exact-pin).
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList(bytes);
  @override
  Stream<Uint8List> readAsByteStream() =>
      Stream.value(Uint8List.fromList(bytes));
}

class _Platform extends FilePickerPlatform with MockPlatformInterfaceMixin {
  List<String>? extensions;
  FileType? type;
  String? called;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    called = 'one';
    this.type = type;
    extensions = allowedExtensions;
    return type == FileType.any ? null : _File('a.cbz', [1]);
  }

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    called = 'many';
    this.type = type;
    return [
      _File('a.cbz', [1]),
      _File('b.cbz', [2]),
    ];
  }
}

void main() {
  late _Platform platform;
  setUp(() => FilePickerPlatform.instance = platform = _Platform());

  test('single pick filters by extension and reads lazily', () async {
    final picker = PluginFilePicker(pickDirectory: () async => []);
    final files = await picker.pickFiles(extensions: ['cbz']);
    expect(platform.called, 'one');
    expect(platform.type, FileType.custom);
    expect(platform.extensions, ['cbz']);
    expect(files.single.name, 'a.cbz');
    expect(files.single.relativePath, isNull);
    expect(await files.single.readBytes(), [1]);
  });

  test('cancel gives an empty list; multiple picks many', () async {
    final picker = PluginFilePicker(pickDirectory: () async => []);
    expect(await picker.pickFiles(), isEmpty);
    expect(platform.type, FileType.any);
    final many = await picker.pickFiles(multiple: true);
    expect(platform.called, 'many');
    expect(many.map((f) => f.name), ['a.cbz', 'b.cbz']);
  });

  test('directory picking is delegated', () async {
    final dir = [PickedFile(name: 'x', read: () async => Uint8List(0))];
    final picker = PluginFilePicker(pickDirectory: () async => dir);
    expect(await picker.pickDirectory(), dir);
  });
}
