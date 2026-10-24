/// The MangaUpdates login sheet: username + password, no OAuth.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/tracking/mangaupdates/mu_models.dart';

/// Logs in with the typed credentials; throws [MuException] on failure.
typedef MuLogin = Future<void> Function(String username, String password);

/// Shows the login sheet; true once [login] succeeded. Escape or a tap
/// outside closes it without logging in.
Future<bool> showMuLoginSheet(BuildContext context, MuLogin login) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: MuLoginForm(
        login: login,
        onDone: () => Navigator.of(sheet).pop(true),
      ),
    ),
  );
  return ok ?? false;
}

/// Username and password fields with a Log in button. Enter in the
/// password field submits; the server's refusal reason is shown inline.
class MuLoginForm extends StatefulWidget {
  /// Creates the form.
  const new({required this.login, required this.onDone, super.key});

  /// Performs the login.
  final MuLogin login;

  /// Called after a successful login.
  final VoidCallback onDone;

  @override
  State<MuLoginForm> createState() => _MuLoginFormState();
}

class _MuLoginFormState extends State<MuLoginForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final user = _username.text.trim();
    final pass = _password.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.login(user, pass);
      if (mounted) widget.onDone();
    } on MuException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Log in to MangaUpdates', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Kartka keeps only the session token, never your password.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('mu-username'),
                controller: _username,
                autofocus: true,
                enabled: !_busy,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('mu-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(
                        dimension: AppSpacing.md,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Log in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
