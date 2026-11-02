import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app_services.dart';
import 'student_checkin_screen.dart';
import 'widgets.dart';

class StudentHomeScreen extends StatefulWidget {
  final Profile profile;
  const StudentHomeScreen({super.key, required this.profile});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  Future<List<Classroom>>? _rooms;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rooms ??= AppScope.of(context).api.classrooms();
  }

  Future<void> _reload() async {
    final next = AppScope.of(context).api.classrooms();
    setState(() => _rooms = next);
    await next.catchError((_) => <Classroom>[]);
  }

  Future<void> _join() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinDialog(),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    try {
      final room = await AppScope.of(context).api.joinClassroom(code.trim());
      if (!mounted) return;
      showSnack(context, 'Joined ${room.name}');
      await _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ClassLink'),
        actions: [
          IconButton(
            tooltip: 'Join a classroom',
            icon: const Icon(Icons.group_add),
            onPressed: _join,
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: services.signOut,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.profile.fullName, style: theme.textTheme.titleLarge),
            if (widget.profile.rollNumber != null)
              Text('Roll ${widget.profile.rollNumber}'),
            const SizedBox(height: 24),
            SizedBox(
              height: 140,
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StudentCheckInScreen()),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.how_to_reg, size: 48),
                    SizedBox(height: 8),
                    Text('Check in to class', style: TextStyle(fontSize: 20)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('My classrooms', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _join,
                  icon: const Icon(Icons.add),
                  label: const Text('Join'),
                ),
              ],
            ),
            FutureBuilder<List<Classroom>>(
              future: _rooms,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  final e = snap.error;
                  return ErrorText(e is ApiException ? e.message : '$e');
                }
                final rooms = snap.data!;
                if (rooms.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'You have not joined any classroom. Ask your teacher '
                      'for the join code and tap Join.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final room in rooms)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.meeting_room_outlined),
                          title: Text(room.name),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Join a classroom'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(labelText: 'Join code from your teacher'),
      onSubmitted: (v) => Navigator.of(context).pop(v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Join'),
      ),
    ],
  );
}
