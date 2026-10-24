import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/platform/platform.dart';

/// A [KartkaPlatform] made of the in-memory fakes.
KartkaPlatform fakePlatform({FakeKartkaHttp? http}) =>
    memoryPlatform(http: http);
