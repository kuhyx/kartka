/// App-wide error capture: everything the user sees fail (or that escapes)
/// lands in the diagnostics log, from where sync reports it to the PC.
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/app/screen_observer.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';

/// Logs uncaught framework (`uncaught.flutter`) and async
/// (`uncaught.async`) errors through [reporter], then defers to the
/// handlers installed before it (presentError, the redacted print).
/// Called once from `main`, after `installRedactedLogging`.
void installErrorReporting(ErrorReporter reporter) {
  final framework = FlutterError.onError;
  FlutterError.onError = (details) {
    if (!details.silent) {
      reporter.report(
        'uncaught.flutter',
        details.exception,
        stack: details.stack,
      );
    }
    framework?.call(details);
  };
  final dispatcher = PlatformDispatcher.instance;
  final async = dispatcher.onError;
  dispatcher.onError = (error, stack) {
    reporter.report('uncaught.async', error, stack: stack);
    return async?.call(error, stack) ?? false;
  };
}

/// Keeps [log]'s route current, so every entry names its screen (a
/// go_router pattern only: ids, URLs and titles never reach the log).
class DiagnosticsRouteObserver implements ScreenObserver {
  /// Reports into [log].
  const new(this.log);

  /// The log stamped with the route.
  final DiagnosticsLog log;

  @override
  void screenChanged(String pattern) => log.route = pattern;
}

/// Words that mark a snackbar as a failure even without the danger hue
/// (`Install failed: ...`, `Refresh failed: ...`, `Browser engine
/// unavailable: ...`, `FooException: ...`).
final _failureText = RegExp(
  r"(exception|error|\bfail(ed|ure)?\b|\bunavailable\b|could ?n[o']?t|"
  r'\bcannot\b|\bunable\b)',
  caseSensitive: false,
);

/// A [ScaffoldMessenger] that reports error snackbars as `ui.snackbar`.
///
/// Mounted once in `MaterialApp.builder`, so it is the nearest messenger of
/// every route and sees every `showSnackBar`, including design_system's
/// `showError` and raw snackbars in screens this layer does not own. A
/// snackbar is an error when it has the danger hue or its text reads as a
/// failure; neutral toasts ("Removed 2 from library") are left alone.
class ReportingScaffoldMessenger extends ScaffoldMessenger {
  /// Reports through [reporter].
  const new({required this.reporter, required super.child, super.key});

  /// Where error snackbars go.
  final ErrorReporter reporter;

  @override
  ScaffoldMessengerState createState() => _ReportingMessengerState();
}

class _ReportingMessengerState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final content = snackBar.content;
    final text = content is Text
        ? content.data ?? content.textSpan?.toPlainText()
        : null;
    final danger = snackBar.backgroundColor == context.statusColors.danger;
    if (danger || (text != null && _failureText.hasMatch(text))) {
      (widget as ReportingScaffoldMessenger).reporter.report(
        'ui.snackbar',
        text ?? 'error snackbar',
        stack: _callerStack(),
      );
    }
    return super.showSnackBar(
      snackBar,
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }
}

/// The current stack minus this file's own frames, so its first kartka
/// frame is the screen that showed the snackbar.
StackTrace _callerStack() => StackTrace.fromString(
  '${StackTrace.current}'
      .split('\n')
      .where((f) => !f.contains('app/error_hooks.dart'))
      .join('\n'),
);
