import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app_services.dart';
import '../teacher/session_controller.dart';
import '../util/permissions.dart';
import 'widgets.dart';

class TeacherSessionScreen extends StatefulWidget {
  final Classroom classroom;
  const TeacherSessionScreen({super.key, required this.classroom});

  @override
  State<TeacherSessionScreen> createState() => _TeacherSessionScreenState();
}

class _TeacherSessionScreenState extends State<TeacherSessionScreen> {
  TeacherSessionController? _controller;
  String? _permissionError;
  bool _exporting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final services = AppScope.of(context);
      _controller = TeacherSessionController(
        api: services.api,
        store: services.store,
        classroom: widget.classroom,
      );
      _start();
    }
  }

  Future<void> _start() async {
    final outcome = await BlePermissions.requestForTeacher();
    if (!mounted) return;
    if (outcome != PermissionOutcome.granted) {
      setState(() {
        _permissionError = outcome == PermissionOutcome.permanentlyDenied
            ? 'Bluetooth permission is turned off for ClassLink. Turn it on '
                  'in system settings, then come back.'
            : 'ClassLink needs Bluetooth permission to run a session.';
      });
      return;
    }
    setState(() => _permissionError = null);
    await _controller!.begin();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<bool> _confirmLeave() async {
    final c = _controller!;
    if (c.phase != SessionPhase.live) return true;
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this session?'),
        content: const Text(
          'Students can only check in while this screen is open. '
          'Ending stops check ins for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep running'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (end != true) return false;
    await c.end();
    return true;
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final file = await _controller!.exportCsv();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Attendance: ${widget.classroom.name}',
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openCorrection(RosterRow row) async {
    final c = _controller!;
    final result = await showModalBottomSheet<(bool, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CorrectionSheet(row: row),
    );
    if (result == null || !mounted) return;
    final error = await c.correct(row, result.$1, result.$2);
    if (mounted) {
      showSnack(context, error ?? 'Saved. The change is in the audit log.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(widget.classroom.name)),
          body: _permissionError != null
              ? CenteredMessage(
                  icon: Icons.bluetooth_disabled,
                  message: _permissionError!,
                  actions: [
                    FilledButton(onPressed: _start, child: const Text('Try again')),
                  ],
                )
              : _body(context, c),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, TeacherSessionController c) {
    switch (c.phase) {
      case SessionPhase.starting:
        return const CenteredMessage(
          message: 'Starting the session…',
          loading: true,
        );
      case SessionPhase.failed:
        return CenteredMessage(
          icon: Icons.error_outline,
          message: c.error ?? 'The session could not start.',
          actions: [
            FilledButton(onPressed: c.begin, child: const Text('Try again')),
          ],
        );
      case SessionPhase.live:
      case SessionPhase.ending:
      case SessionPhase.ended:
        return _liveBody(context, c);
    }
  }

  Widget _liveBody(BuildContext context, TeacherSessionController c) {
    final theme = Theme.of(context);
    final live = c.phase == SessionPhase.live;
    final ended = c.phase == SessionPhase.ended;
    return RefreshIndicator(
      onRefresh: c.refreshRoster,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: live
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(live ? Icons.bluetooth_audio : Icons.stop_circle_outlined),
                      const SizedBox(width: 8),
                      Text(live
                          ? 'Live: students can check in now'
                          : (ended ? 'Session ended' : 'Ending…')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Room code', style: theme.textTheme.labelLarge),
                  Text(
                    c.roomCode ?? '········',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Students see this code on their phone. The secret part '
                    'changes every few seconds.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Text('${c.presentCount} of ${c.roster.length} present'
                      ' · ${c.broadcaster.readsServed} phone reads'),
                ],
              ),
            ),
          ),
          if (c.warning != null) ...[
            const SizedBox(height: 8),
            ErrorText(c.warning!),
          ],
          const SizedBox(height: 12),
          if (!ended)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.stop),
              label: const Text('End session'),
              onPressed: live ? c.end : null,
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.ios_share),
              label: Text(_exporting ? 'Preparing…' : 'Export CSV'),
              onPressed: _exporting ? null : _export,
            ),
          const SizedBox(height: 16),
          Text('Roster', style: theme.textTheme.titleMedium),
          Text('Tap a student to correct their mark.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          if (c.roster.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No students have joined this classroom yet.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final row in c.roster)
            Card(
              child: ListTile(
                onTap: () => _openCorrection(row),
                leading: Icon(
                  row.isPresent ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: row.isPresent ? Colors.green : theme.disabledColor,
                ),
                title: Text(row.fullName),
                subtitle: Text([
                  if (row.rollNumber != null) row.rollNumber!,
                  if (row.isManual) 'corrected by you',
                  if (!row.isManual && row.medianRssi != null)
                    '${row.medianRssi} dBm',
                ].join(' · ')),
                trailing: Text(row.status ?? 'absent'),
              ),
            ),
        ],
      ),
    );
  }
}

class _CorrectionSheet extends StatefulWidget {
  final RosterRow row;
  const _CorrectionSheet({required this.row});

  @override
  State<_CorrectionSheet> createState() => _CorrectionSheetState();
}

class _CorrectionSheetState extends State<_CorrectionSheet> {
  late bool _present = !widget.row.isPresent;
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Correct ${widget.row.fullName}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Present')),
              ButtonSegment(value: false, label: Text('Absent')),
            ],
            selected: {_present},
            onSelectionChanged: (s) => setState(() => _present = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason (required, saved in the audit log)',
              hintText: 'Phone battery died, seen in class',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            ErrorText(_error!),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final reason = _reason.text.trim();
              if (reason.length < 5) {
                setState(() => _error = 'Write at least 5 characters.');
                return;
              }
              Navigator.of(context).pop((_present, reason));
            },
            child: const Text('Save correction'),
          ),
        ],
      ),
    );
  }
}
