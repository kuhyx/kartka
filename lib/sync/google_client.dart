/// Google sign-in configuration for Kartka's sync account.
library;

/// The `kuhy-syncs` project's **Web** OAuth client id, the one every kuhy app
/// ships (todo's `kServerClientId`).
///
/// Public by design, exactly like the Web API key in `sync_config.dart`: it
/// ships inside every APK, and the database rules pinned to the sync uid --
/// not its secrecy -- protect the data. A const rather than a
/// `--dart-define` on purpose: an empty compile-time value would silently
/// hide the button in any build made without the define file.
///
/// It plays two roles: the `serverClientId` (token audience) for the Android
/// plugin, and the `clientId` of the Google Identity Services button on the
/// web build. The Android half additionally needs an Android client for
/// `com.kuhy.kartka` + the signing SHA-1, and the web half needs
/// `http://127.0.0.1:47391` as an authorised JavaScript origin on this client;
/// `tools/sync/register_google_signin.sh` walks both.
const kKartkaGoogleClientId =
    '845446124781-prdoherj0v64vc6egvvcp3l0693khaur.apps.googleusercontent.com';
