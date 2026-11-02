import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app_services.dart';
import 'teacher_session_screen.dart';
import 'widgets.dart';

class TeacherHomeScreen extends StatefulWidget {
  final Profile profile;
  const TeacherHomeScreen({super.key, required this.profile});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
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

  Future<void> _createClassroom() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final room = await AppScope.of(context).api.createClassroom(name.trim());
      if (!mounted) return;
      showSnack(context, 'Created ${room.name}. Join code ${room.joinCode}');
      await _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My classrooms'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: services.signOut,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createClassroom,
        icon: const Icon(Icons.add),
        label: const Text('New classroom'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Classroom>>(
          future: _rooms,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const CenteredMessage(message: 'Loading…', loading: true);
            }
            if (snap.hasError) {
              final e = snap.error;
              return ListView(children: [
                CenteredMessage(
                  icon: Icons.cloud_off,
                  message: e is ApiException ? e.message : '$e',
                  actions: [
                    FilledButton(onPressed: _reload, child: const Text('Retry')),
                  ],
                ),
              ]);
            }
            final rooms = snap.data!;
            if (rooms.isEmpty) {
              return ListView(children: const [
                CenteredMessage(
                  icon: Icons.meeting_room_outlined,
                  message: 'No classrooms yet. Create one, then share its '
                      'join code with your students.',
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: rooms.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text('Hello, ${widget.profile.fullName}',
                      style: Theme.of(context).textTheme.titleMedium);
                }
                return _ClassroomCard(room: rooms[i - 1]);
              },
            );
          },
        ),
      ),
    );
  }
}

class _ClassroomCard extends StatelessWidget {
  final Classroom room;
  const _ClassroomCard({required this.room});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(room.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Join code: ${room.joinCode}'),
                IconButton(
                  tooltip: 'Copy join code',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: room.joinCode));
                    showSnack(context, 'Join code copied');
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start attendance'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TeacherSessionScreen(classroom: room),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New classroom'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Name',
        hintText: 'UCS503 Software Engineering, 3C11',
      ),
      onSubmitted: (v) => Navigator.of(context).pop(v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Create'),
      ),
    ],
  );
}
