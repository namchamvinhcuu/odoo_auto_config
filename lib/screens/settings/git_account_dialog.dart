import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';

class GitAccountDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const GitAccountDialog({super.key, this.existing});

  @override
  State<GitAccountDialog> createState() => _GitAccountDialogState();
}

class _GitAccountDialogState extends State<GitAccountDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _tokenController;
  bool _tokenObscured = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: (e?['name'] ?? '').toString());
    _usernameController = TextEditingController(text: (e?['username'] ?? '').toString());
    _emailController = TextEditingController(text: (e?['email'] ?? '').toString());
    _tokenController = TextEditingController(text: (e?['token'] ?? '').toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty &&
      _tokenController.text.trim().isNotEmpty;

  void _save() {
    Navigator.pop(context, {
      'name': _nameController.text.trim(),
      'username': _usernameController.text.trim(),
      'email': _emailController.text.trim(),
      'token': _tokenController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Text(widget.existing != null ? 'Edit Account' : 'Add Git Account'),
        const Spacer(),
        AppDialog.closeButton(context),
      ]),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name *',
                hintText: 'e.g. namchamvinhcuu',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'GitHub username',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'user@example.com',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _tokenController,
              obscureText: _tokenObscured,
              decoration: InputDecoration(
                labelText: 'Token *',
                hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                      _tokenObscured ? Icons.visibility_off : Icons.visibility),
                  onPressed: () =>
                      setState(() => _tokenObscured = !_tokenObscured),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
