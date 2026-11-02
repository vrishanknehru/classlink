import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app_services.dart';
import 'widgets.dart';

/// First sign in: name and roll number. The server decides the role from its
/// teacher allowlist, so a student cannot make themselves a teacher here.
class ProfileSetupScreen extends StatefulWidget {
  final VoidCallback onCreated;
  const ProfileSetupScreen({super.key, required this.onCreated});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _roll = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _roll.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your full name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).api.createProfile(
            fullName: _name.text.trim(),
            rollNumber: _roll.text.trim(),
          );
      widget.onCreated();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your profile'),
        actions: [
          TextButton(
            onPressed: services.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Signed in as ${services.auth.session?.email ?? 'unknown'}'),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _roll,
            decoration: const InputDecoration(
              labelText: 'Roll number',
              helperText: 'Students must fill this. Teachers can leave it empty.',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Continue'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorText(_error!),
          ],
        ],
      ),
    );
  }
}
