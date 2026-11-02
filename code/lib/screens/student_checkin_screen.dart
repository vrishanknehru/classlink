import 'package:flutter/material.dart';

import '../app_services.dart';
import '../attendance/check_in_controller.dart';
import '../util/permissions.dart';
import 'widgets.dart';

class StudentCheckInScreen extends StatefulWidget {
  const StudentCheckInScreen({super.key});

  @override
  State<StudentCheckInScreen> createState() => _StudentCheckInScreenState();
}

class _StudentCheckInScreenState extends State<StudentCheckInScreen> {
  CheckInController? _controller;
  String? _permissionError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final services = AppScope.of(context);
      _controller = CheckInController(api: services.api, keys: services.keys);
      _start();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final outcome = await BlePermissions.requestForStudent();
    if (!mounted) return;
    if (outcome != PermissionOutcome.granted) {
      setState(() {
        _permissionError = outcome == PermissionOutcome.permanentlyDenied
            ? 'Bluetooth permission is turned off for ClassLink. Turn it on '
                  'in system settings to check in.'
            : 'ClassLink needs Bluetooth permission to check in.';
      });
      return;
    }
    setState(() => _permissionError = null);
    await _controller!.start();
  }

  (IconData, String) _describe(CheckInController c) {
    switch (c.step) {
      case CheckInStep.idle:
        return (Icons.bluetooth, 'Ready to check in.');
      case CheckInStep.searching:
        return (Icons.bluetooth_searching, 'Looking for your teacher\'s phone…');
      case CheckInStep.readingCode:
        return (Icons.bluetooth_connected, 'Found it. Reading the room code…');
      case CheckInStep.verifying:
        return (Icons.cloud_sync, 'Checking the code with the server…');
      case CheckInStep.measuring:
        return (Icons.network_check, 'Measuring signal. Hold still for a few seconds…');
      case CheckInStep.tooFar:
        return (Icons.directions_walk, 'You look too far away. Move closer to the teacher.');
      case CheckInStep.submitting:
        return (Icons.send, 'Sending your signed check in…');
      case CheckInStep.done:
        return (Icons.check_circle, 'You are marked present.');
      case CheckInStep.failed:
        return (Icons.error_outline, c.error ?? 'Check in failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Check in')),
      body: _permissionError != null
          ? CenteredMessage(
              icon: Icons.bluetooth_disabled,
              message: _permissionError!,
              actions: [
                FilledButton(onPressed: _start, child: const Text('Try again')),
              ],
            )
          : ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final (icon, text) = _describe(c);
                final done = c.step == CheckInStep.done;
                final failed = c.step == CheckInStep.failed;
                final color = done
                    ? Colors.green
                    : (failed ? theme.colorScheme.error : theme.colorScheme.primary);
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 24),
                    Icon(icon, size: 96, color: color),
                    const SizedBox(height: 16),
                    Text(text,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium),
                    if (c.isBusy) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 24),
                    if (c.roomCode != null)
                      _InfoRow(
                        label: 'Room code',
                        value: c.roomCode!,
                        hint: 'Should match the teacher\'s screen',
                      ),
                    if (c.lastMedianRssi != null)
                      _InfoRow(
                        label: 'Your signal',
                        value: '${c.lastMedianRssi} dBm',
                        hint: c.thresholdDbm == null
                            ? null
                            : 'Needs ${c.thresholdDbm} dBm or stronger',
                      ),
                    if (done && c.result != null)
                      _InfoRow(
                        label: 'Recorded at',
                        value: TimeOfDay.fromDateTime(
                          c.result!.attendance.recordedAt.toLocal(),
                        ).format(context),
                      ),
                    const SizedBox(height: 24),
                    if (c.isBusy)
                      OutlinedButton(
                        onPressed: c.cancel,
                        child: const Text('Cancel'),
                      )
                    else if (done)
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Done'),
                      )
                    else
                      FilledButton(
                        onPressed: _start,
                        child: Text(failed ? 'Try again' : 'Start check in'),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'The server makes the final decision. Your phone signs '
                      'the check in with a key that only this phone holds.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;

  const _InfoRow({required this.label, required this.value, this.hint});

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    subtitle: hint == null ? null : Text(hint!),
    trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
  );
}
