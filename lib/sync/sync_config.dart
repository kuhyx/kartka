/// Kartka's Firebase sync project (the shared `kuhy-syncs` RTDB).
library;

import 'package:crdt_sync/crdt_sync.dart' show FirebaseProject;
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show SyncApp;

/// The shared project every kuhy app syncs through. Safe to commit: the Web
/// API key is a public identifier that already ships inside every APK, and
/// the database rules (pinned to [SyncApp.expectedUid]), not secrecy, are
/// what protect the data. The account password is never in source; it is
/// entered once on the sync account screen and kept in the OS keystore.
const SyncApp kKartkaSync = SyncApp(
  project: FirebaseProject(
    apiKey: 'AIzaSyCF_sA3xCMehAYXK8eND-rAygb9NXXW_8E',
    // Must be the regional host: `*.firebaseio.com` answers 404.
    databaseUrl:
        'https://kuhy-syncs-default-rtdb.europe-west1.firebasedatabase.app',
  ),
  expectedUid: 'OvA2REQyLIhAHOEjzwS1o877rgG3',
);
