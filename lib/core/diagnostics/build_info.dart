/// Which build is running, as `scripts/build_android.sh` stamps it with
/// `--dart-define`: versionCode is the commit count (monotonic), versionName
/// is `<pubspec version>-<short sha>`. Both are empty/zero in a build without
/// the defines (desktop web, tests), and reports then simply omit them.
library;

/// The running build's versionCode (0 when unknown).
const kartkaVersionCode = int.fromEnvironment('KARTKA_VERSION_CODE');

/// The running build's versionName (empty when unknown).
const kartkaVersionName = String.fromEnvironment('KARTKA_VERSION_NAME');
