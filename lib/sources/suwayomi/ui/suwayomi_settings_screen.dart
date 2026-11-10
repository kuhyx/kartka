import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/ui/snack_mark.dart';
import 'package:kartka/sources/suwayomi/suwayomi_exceptions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';

const _tap = Size.square(48);

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

  /// Last connection test: success, and the server's name or the error.
  ({bool ok, String detail})? _status;
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
    if (mounted) {
      showMark(context, const Icon(Icons.check, semanticLabel: 'Saved'));
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    ({bool ok, String detail}) status;
    try {
      status = (ok: true, detail: await widget.testConnection(_typed));
    } on SuwayomiException catch (e) {
      status = (ok: false, detail: e.message);
    } on Object catch (e) {
      status = (ok: false, detail: '$e');
    }
    if (mounted) {
      setState(() {
        _testing = false;
        _status = status;
      });
    }
  }

  /// The test result: a green tick or a red mark, then the server's name or
  /// its error (both content).
  Widget _statusRow(({bool ok, String detail}) s) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          s.ok ? Icons.check_circle : Icons.error_outline,
          color: s.ok ? colors.primary : colors.error,
          semanticLabel: s.ok ? 'Connected' : 'Failed',
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(redactUrlQueries(s.detail))),
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    IconData icon,
    String semanticLabel, {
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
      decoration: InputDecoration(
        prefixIcon: Icon(icon, semanticLabel: semanticLabel),
      ),
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
        appBar: AppBar(
          title: const Icon(
            Icons.dns_outlined,
            semanticLabel: 'Suwayomi server',
          ),
        ),
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
                  _field(
                    _url,
                    Icons.link,
                    'Server URL',
                    keyboard: TextInputType.url,
                  ),
                  _field(_user, Icons.person_outline, 'Username'),
                  _field(
                    _pass,
                    Icons.key,
                    'Password',
                    secret: true,
                    last: true,
                  ),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      IconButton.filled(
                        style: IconButton.styleFrom(minimumSize: _tap),
                        onPressed: _save,
                        icon: const Icon(Icons.save, semanticLabel: 'Save'),
                      ),
                      IconButton.outlined(
                        style: IconButton.styleFrom(minimumSize: _tap),
                        onPressed: _testing ? null : _test,
                        icon: const Icon(
                          Icons.network_check,
                          semanticLabel: 'Test connection',
                        ),
                      ),
                      IconButton(
                        style: IconButton.styleFrom(minimumSize: _tap),
                        onPressed: widget.onOpenExtensions,
                        icon: const Icon(
                          Icons.extension,
                          semanticLabel: 'Extensions',
                        ),
                      ),
                    ],
                  ),
                  if (_testing || _status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: _testing
                          ? const LinearProgressIndicator()
                          : _statusRow(_status!),
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
