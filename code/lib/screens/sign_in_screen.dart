import 'package:flutter/material.dart';

import '../app_services.dart';
import '../auth/auth_service.dart';
import 'widgets.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _devToken = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _devToken.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = AppScope.of(context).auth;
    final email = _email.text.trim();
    if (!email.contains('@') || _password.text.length < 6) {
      setState(() => _error = 'Enter your email and a password of 6+ characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_creating) {
        final needsConfirm = await auth.signUp(email, _password.text);
        if (needsConfirm && mounted) {
          setState(() {
            _creating = false;
            _info = 'Account created. Confirm the link in your email, then sign in.';
          });
        }
      } else {
        await auth.signIn(email, _password.text);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useDevToken() async {
    try {
      await AppScope.of(context).auth.useDeveloperToken(_devToken.text);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.bluetooth_searching,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('ClassLink',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium),
                  Text('Attendance by Bluetooth, checked by the server',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 32),
                  if (services.config.hasSupabase) ...[
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'College email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Password'),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_busy
                            ? 'Please wait…'
                            : (_creating ? 'Create account' : 'Sign in')),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _creating = !_creating;
                                _error = null;
                              }),
                      child: Text(_creating
                          ? 'I already have an account'
                          : 'New here? Create an account'),
                    ),
                  ] else ...[
                    Text(
                      'Developer sign in. This build has no Supabase settings, '
                      'so paste a token from backend/scripts/dev_token.py.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _devToken,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Bearer token'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _useDevToken,
                      child: const Text('Use token'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    ErrorText(_error!),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(_info!),
                  ],
                  const SizedBox(height: 24),
                  Text('Server: ${services.config.apiBaseUrl}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
