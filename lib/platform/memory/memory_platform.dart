/// In-memory platform for tests of every part.
library;

import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/platform/platform.dart';

export 'memory_browser.dart';
export 'memory_fakes.dart';
export 'memory_stores.dart';

/// A [KartkaPlatform] of in-memory fakes; pass any piece to override it.
KartkaPlatform memoryPlatform({
  FakeKartkaHttp? http,
  MemoryBlobStore? blobs,
  MemoryKeyValueStore? kv,
  MemoryKeyValueStore? secrets,
  FakeFilePicker? filePicker,
  FakeOAuthRedirect? oauth,
  KartkaBrowser? browser,
  MemoryBlobStore? diagnostics,
}) => KartkaPlatform(
  http: http ?? FakeKartkaHttp(),
  blobs: blobs ?? MemoryBlobStore(),
  kv: kv ?? MemoryKeyValueStore(),
  secrets: secrets ?? MemoryKeyValueStore(),
  filePicker: filePicker ?? FakeFilePicker(),
  oauth: oauth ?? FakeOAuthRedirect(),
  browser: browser ?? const UnavailableBrowser(),
  diagnostics: diagnostics ?? MemoryBlobStore(),
);
