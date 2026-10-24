/// Asks for the sync passphrase twice (DOCS-contracts-runtime §16).
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Shows the dialog; the entered passphrase, or null when cancelled.
Future<String?> askPassphrase(BuildContext context, {required bool change}) =>
    showDialog<String>(
      context: context,
      builder: (_) => PassphraseDialog(change: change),
    );

/// Two obscured fields; Save is enabled once they match and are not empty.
class PassphraseDialog extends StatefulWidget {
  /// [change]: this device already has one.
  const new({required this.change, super.key});

  /// Whether this replaces an existing passphrase.
  final bool change;

  @override
  State<PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<PassphraseDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  bool get _valid => _first.text.isNotEmpty && _first.text == _second.text;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.change ? 'Change' : 'Set'} sync passphrase'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Use the same passphrase on every device. It never leaves this '
          'device and encrypts the synced Suwayomi login.',
        ),
        const SizedBox(height: AppSpacing.md),
        _field(_first, 'Passphrase'),
        const SizedBox(height: AppSpacing.sm),
        _field(_second, 'Repeat passphrase'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _valid ? () => Navigator.of(context).pop(_first.text) : null,
        child: const Text('Save'),
      ),
    ],
  );

  Widget _field(TextEditingController c, String label) => TextField(
    controller: c,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() {}),
  );
}
