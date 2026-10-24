/// Optional login UI for trackers without OAuth (contracts §15).
library;

import 'package:flutter/widgets.dart';

/// A `Tracker` that logs in with typed credentials instead of an OAuth
/// redirect. The track sheet calls [showLogin] for these trackers and
/// `Tracker.login()` for every other one.
abstract interface class CredentialsLogin {
  /// Shows the tracker's own login UI; completes when it closes, whether
  /// the user logged in or cancelled.
  Future<void> showLogin(BuildContext context);
}
