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
    title: Icon(
      widget.change ? Icons.edit_outlined : Icons.key_outlined,
      size: 48,
      semanticLabel: '${widget.change ? 'Change' : 'Set'} sync passphrase',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(_first, Icons.key_outlined, 'Passphrase'),
        const SizedBox(height: AppSpacing.sm),
        _field(_second, Icons.repeat, 'Repeat passphrase'),
      ],
    ),
    actions: [
      IconButton(
        style: IconButton.styleFrom(minimumSize: _button),
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
      ),
      IconButton.filled(
        style: IconButton.styleFrom(minimumSize: _button),
        onPressed: _valid ? () => Navigator.of(context).pop(_first.text) : null,
        icon: const Icon(Icons.check, semanticLabel: 'Save'),
      ),
    ],
  );

  static const _button = Size.square(48);

  Widget _field(TextEditingController c, IconData icon, String spoken) =>
      TextField(
        key: Key('passphrase-$spoken'),
        controller: c,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, semanticLabel: spoken),
        ),
        onChanged: (_) => setState(() {}),
      );
}
