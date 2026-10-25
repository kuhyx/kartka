import 'dart:ui';

/// A frame whose build took [buildMs] and raster [rasterMs] milliseconds.
FrameTiming frame(double buildMs, [double rasterMs = 0]) {
  final build = (buildMs * 1000).round();
  final raster = (rasterMs * 1000).round();
  return FrameTiming(
    vsyncStart: 0,
    buildStart: 10,
    buildFinish: 10 + build,
    rasterStart: 20 + build,
    rasterFinish: 20 + build + raster,
    rasterFinishWallTime: 20 + build + raster,
  );
}
