import 'package:flutter/material.dart';

import '../ble/student_scanner.dart';
import '../util/permissions.dart';

class StudentCheckinScreen extends StatefulWidget {
  const StudentCheckinScreen({super.key});

  @override
  State<StudentCheckinScreen> createState() => _StudentCheckinScreenState();
}

class _StudentCheckinScreenState extends State<StudentCheckinScreen> {
  final StudentScanner _scanner = StudentScanner();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rollController = TextEditingController();
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _scanner.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _scanner.removeListener(_onChanged);
    _scanner.dispose();
    _nameController.dispose();
    _rollController.dispose();
    super.dispose();
  }

  Future<void> _startScanning() async {
    if (_nameController.text.trim().isEmpty ||
        _rollController.text.trim().isEmpty) {
      setState(() {
        _statusMessage = 'Enter your name and roll number first.';
      });
      return;
    }
    setState(() => _statusMessage = null);
    final outcome = await BlePermissions.requestForStudent();
    if (outcome != PermissionOutcome.granted) {
      setState(() {
        _statusMessage = outcome == PermissionOutcome.permanentlyDenied
            ? 'Bluetooth/location permissions are permanently denied. '
                  'Enable them in system settings to check in.'
            : 'Bluetooth/location permissions are required to check in.';
      });
      return;
    }
    await _scanner.startScanning(
      name: _nameController.text.trim(),
      rollNumber: _rollController.text.trim(),
    );
  }

  String _statusFor(ScanState state) {
    switch (state) {
      case ScanState.idle:
        return 'Not scanning';
      case ScanState.scanning:
        return 'Scanning for classroom…';
      case ScanState.tooFar:
        return 'Too far — move closer to the teacher\'s device';
      case ScanState.connecting:
        return 'Found it! Checking in…';
      case ScanState.checkedIn:
        return 'Checked in ✅';
      case ScanState.failure:
        return _scanner.errorMessage ?? 'Something went wrong';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy =
        _scanner.state == ScanState.scanning ||
        _scanner.state == ScanState.tooFar ||
        _scanner.state == ScanState.connecting;

    return Scaffold(
      appBar: AppBar(title: const Text('Student — Check In')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              enabled: !isBusy,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rollController,
              enabled: !isBusy,
              decoration: const InputDecoration(
                labelText: 'Roll number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isBusy
                  ? null
                  : (_scanner.state == ScanState.checkedIn
                        ? () => setState(() {
                            _statusMessage = null;
                          })
                        : _startScanning),
              child: Text(
                _scanner.state == ScanState.checkedIn
                    ? 'Check In Again'
                    : 'Start Check-In',
              ),
            ),
            if (isBusy) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _scanner.stopScanning(),
                child: const Text('Cancel'),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              _statusMessage ?? _statusFor(_scanner.state),
              style: TextStyle(
                fontSize: 16,
                color: _scanner.state == ScanState.checkedIn
                    ? Colors.green
                    : null,
              ),
            ),
            if (_scanner.detectedSessionCode != null) ...[
              const SizedBox(height: 8),
              Text('Session code: ${_scanner.detectedSessionCode}'),
            ],
            if (_scanner.lastMedianRssi != null) ...[
              const SizedBox(height: 8),
              Text('Last signal: ${_scanner.lastMedianRssi} dBm'),
            ],
          ],
        ),
      ),
    );
  }
}
