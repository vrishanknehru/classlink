import 'dart:io';

import 'package:flutter/material.dart';

import '../attendance/csv_export.dart';
import '../ble/teacher_broadcaster.dart';
import '../util/permissions.dart';

class TeacherSessionScreen extends StatefulWidget {
  const TeacherSessionScreen({super.key});

  @override
  State<TeacherSessionScreen> createState() => _TeacherSessionScreenState();
}

class _TeacherSessionScreenState extends State<TeacherSessionScreen> {
  final TeacherBroadcaster _broadcaster = TeacherBroadcaster();
  final TextEditingController _classroomController = TextEditingController(
    text: 'Room 101',
  );
  File? _exportedFile;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _broadcaster.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _broadcaster.removeListener(_onChanged);
    _broadcaster.dispose();
    _classroomController.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    setState(() {
      _exportedFile = null;
      _statusMessage = null;
    });
    final outcome = await BlePermissions.requestForTeacher();
    if (outcome != PermissionOutcome.granted) {
      setState(() {
        _statusMessage = outcome == PermissionOutcome.permanentlyDenied
            ? 'Bluetooth/location permissions are permanently denied. '
                  'Enable them in system settings to broadcast a session.'
            : 'Bluetooth/location permissions are required to broadcast a session.';
      });
      return;
    }
    await _broadcaster.startSession();
  }

  Future<void> _endSession() async {
    final classroomName = _classroomController.text.trim().isEmpty
        ? 'Classroom'
        : _classroomController.text.trim();
    final sessionStartedAt = _broadcaster.sessionStartedAt ?? DateTime.now();
    final records = _broadcaster.records;
    await _broadcaster.endSession();
    if (records.isEmpty) {
      setState(() {
        _statusMessage = 'Session ended. No check-ins were recorded.';
      });
      return;
    }
    final file = await AttendanceCsvExport.saveToFile(
      classroomName: classroomName,
      sessionStartedAt: sessionStartedAt,
      records: records,
    );
    setState(() {
      _exportedFile = file;
      _statusMessage = 'Session ended. Attendance exported.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAdvertising = _broadcaster.state == BroadcastState.advertising;
    final isStarting = _broadcaster.state == BroadcastState.starting;

    return Scaffold(
      appBar: AppBar(title: const Text('Teacher — Session')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _classroomController,
              enabled: !isAdvertising && !isStarting,
              decoration: const InputDecoration(
                labelText: 'Classroom / session name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (isAdvertising && _broadcaster.sessionCode != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('Session code'),
                      Text(
                        _broadcaster.sessionCode!,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isStarting
                  ? null
                  : (isAdvertising ? _endSession : _startSession),
              child: Text(
                isStarting
                    ? 'Starting…'
                    : (isAdvertising ? 'End Session & Export CSV' : 'Start Session'),
              ),
            ),
            if (_broadcaster.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _broadcaster.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(_statusMessage!),
            ],
            if (_exportedFile != null) ...[
              const SizedBox(height: 8),
              Text(
                'Saved to: ${_exportedFile!.path}',
                style: const TextStyle(fontSize: 12),
              ),
              TextButton(
                onPressed: () => AttendanceCsvExport.share(
                  _exportedFile!,
                  classroomName: _classroomController.text.trim(),
                ),
                child: const Text('Share CSV'),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Checked in',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            Expanded(
              child: _broadcaster.records.isEmpty
                  ? const Center(child: Text('No check-ins yet'))
                  : ListView.builder(
                      itemCount: _broadcaster.records.length,
                      itemBuilder: (context, index) {
                        final record = _broadcaster.records[index];
                        return ListTile(
                          title: Text(record.name),
                          subtitle: Text('Roll ${record.rollNumber}'),
                          trailing: Text('${record.medianRssi} dBm'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
