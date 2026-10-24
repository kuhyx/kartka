import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kartka/sources/suwayomi/suwayomi_exceptions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';

/// Server URL and basic-auth credentials, with a connection test.
class SuwayomiSettingsScreen extends StatefulWidget {
  /// Creates the screen.
  const new({
    required this.store,
    required this.testConnection,
    required this.onOpenExtensions,
    this.syncProblems,
    super.key,
  });

  /// Where the settings live (credentials in secret storage).
  final SuwayomiSettingsStore store;

  /// Checks the given (unsaved) settings; returns the server's name.
  final Future<String> Function(SuwayomiSettings settings) testConnection;

  /// Opens the extensions screen.
  final VoidCallback onOpenExtensions;

  /// Settings sync problems for these fields, e.g. a synced password this
  /// device could not decrypt.
  final Stream<List<String>>? syncProblems;

  @override
  State<SuwayomiSettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SuwayomiSettingsScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _status;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_fill());
  }

  Future<void> _fill() async {
    final s = await widget.store.load();
    if (!mounted) return;
    _url.text = s.serverUrl;
    _user.text = s.username;
    _pass.text = s.password;
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  SuwayomiSettings get _typed => SuwayomiSettings(
    serverUrl: _url.text.trim(),
    username: _user.text.trim(),
    password: _pass.text,
  );

  Future<void> _save() async {
    await widget.store.save(_typed);
    if (mounted) showToast(context, 'Saved');
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    String status;
    try {
      status = 'Connected: ${await widget.testConnection(_typed)}';
    } on SuwayomiException catch (e) {
      status = 'Failed: ${e.message}';
    } on Object catch (e) {
      status = 'Failed: $e';
    }
    if (mounted) {
      setState(() {
        _testing = false;
        _status = status;
      });
    }
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool secret = false,
    TextInputType? keyboard,
    bool last = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: TextField(
      controller: c,
      obscureText: secret,
      autocorrect: false,
      keyboardType: keyboard,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onSubmitted: last ? (_) => _save() : null,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.maybePop(context),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('Suwayomi server')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StreamBuilder<List<String>>(
                    stream: widget.syncProblems,
                    builder: (context, snap) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final problem in snap.data ?? const <String>[])
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            child: Text(
                              problem,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _field(_url, 'Server URL', keyboard: TextInputType.url),
                  _field(_user, 'Username'),
                  _field(_pass, 'Password', secret: true, last: true),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton(onPressed: _save, child: const Text('Save')),
                      OutlinedButton(
                        onPressed: _testing ? null : _test,
                        child: const Text('Test connection'),
                      ),
                      TextButton(
                        onPressed: widget.onOpenExtensions,
                        child: const Text('Extensions'),
                      ),
                    ],
                  ),
                  if (_testing || _status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: _testing
                          ? const LinearProgressIndicator()
                          : Text(_status!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
