import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app_services.dart';
import 'profile_setup_screen.dart';
import 'sign_in_screen.dart';
import 'student_home_screen.dart';
import 'teacher_home_screen.dart';
import 'widgets.dart';

/// Decides the first screen: sign in, profile setup, or the role's home.
class HomeGate extends StatelessWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final session = auth.session;
        if (session == null) return const SignInScreen();
        return _ProfileLoader(key: ValueKey(session.userId));
      },
    );
  }
}

class _ProfileLoader extends StatefulWidget {
  const _ProfileLoader({super.key});

  @override
  State<_ProfileLoader> createState() => _ProfileLoaderState();
}

class _ProfileLoaderState extends State<_ProfileLoader> {
  Future<Profile?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  /// Null means the account has no profile yet.
  Future<Profile?> _load() async {
    final services = AppScope.of(context);
    try {
      final profile = await services.api.me();
      if (!profile.isTeacher) {
        await services.ensureDeviceBound(profile.id);
      }
      return profile;
    } on ApiException catch (e) {
      if (e.code == 'profile_required') return null;
      rethrow;
    }
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: CenteredMessage(message: 'Loading your account…', loading: true),
          );
        }
        if (snap.hasError) {
          final error = snap.error;
          return Scaffold(
            body: CenteredMessage(
              icon: Icons.cloud_off,
              message: error is ApiException ? error.message : '$error',
              actions: [
                FilledButton(onPressed: _reload, child: const Text('Retry')),
                TextButton(
                  onPressed: () => AppScope.of(context).signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          );
        }
        final profile = snap.data;
        if (profile == null) return ProfileSetupScreen(onCreated: _reload);
        return profile.isTeacher
            ? TeacherHomeScreen(profile: profile)
            : StudentHomeScreen(profile: profile);
      },
    );
  }
}
