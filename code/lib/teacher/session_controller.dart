import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../api/claim_protocol.dart';
import '../api/models.dart';
import '../ble/teacher_broadcaster.dart';
import '../util/secure_store.dart';

enum SessionPhase { starting, live, ending, ended, failed }

/// Runs one class session on the teacher phone: starts it on the server,
/// keeps the BLE token fresh, polls the roster and ends it.
class TeacherSessionController extends ChangeNotifier {
  final ClassLinkApi api;
  final SecureStore store;
  final Classroom classroom;
  final TeacherBroadcaster broadcaster;

  TeacherSessionController({
    required this.api,
    required this.store,
    required this.classroom,
    TeacherBroadcaster? broadcaster,
  }) : broadcaster = broadcaster ?? TeacherBroadcaster() {
    this.broadcaster.addListener(notifyListeners);
  }

  SessionPhase _phase = SessionPhase.starting;
  SessionPhase get phase => _phase;

  SessionInfo? _session;
  SessionInfo? get session => _session;

  String? _sessionId;

  String? _error;
  String? get error => _error;

  /// Problems that do not stop the session, such as a missed roster poll.
  String? _warning;
  String? get warning => _warning;

  List<RosterRow> _roster = const [];
  List<RosterRow> get roster => _roster;
  int get presentCount => _roster.where((r) => r.isPresent).length;

  String? _roomCode;
  String? get roomCode => _roomCode;

  DateTime? _tokenExpiresAt;
  DateTime? get tokenExpiresAt => _tokenExpiresAt;

  Timer? _tokenTimer;
  Timer? _rosterTimer;
  bool _disposed = false;

  String get _activeKey => 'classlink.active_session.${classroom.id}';

  /// Start a new session, or pick up the one this phone left running.
  Future<void> begin() async {
    _phase = SessionPhase.starting;
    _error = null;
    _notify();
    try {
      try {
        final created = await api.startSession(classroom.id);
        _session = created;
        _sessionId = created.id;
        await store.write(_activeKey, created.id);
      } on ApiException catch (e) {
        if (e.code != 'active_session_exists') rethrow;
        final saved = await store.read(_activeKey);
        if (saved == null) {
          throw const _SessionError(
            'A session for this classroom is already running on another '
            'phone. End it there first.',
          );
        }
        _sessionId = saved;
      }
      await _refreshToken();
      await broadcaster.start();
      if (broadcaster.state != BroadcastState.broadcasting) {
        throw _SessionError(
          broadcaster.errorMessage ?? 'Bluetooth did not start.',
        );
      }
      _phase = SessionPhase.live;
      _notify();
      await refreshRoster();
      _rosterTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => refreshRoster(),
      );
    } on ApiException catch (e) {
      _failWith(e.message);
    } on _SessionError catch (e) {
      _failWith(e.message);
    }
  }

  Future<void> _refreshToken() async {
    final id = _sessionId;
    if (id == null) return;
    _tokenTimer?.cancel();
    try {
      final token = await api.currentToken(id);
      broadcaster.updateToken(hexToBytes(token.tokenHex));
      _roomCode = roomCodeOf(hexToBytes(token.tokenHex));
      _tokenExpiresAt = token.expiresAt;
      _warning = null;
      // Fetch a few times per period so a late or early phone clock never
      // leaves an expired token on air.
      final every = Duration(
        milliseconds: math.max(2000, math.min(20000, token.periodSeconds * 333)),
      );
      _tokenTimer = Timer(every, _refreshToken);
    } on ApiException catch (e) {
      if (e.code == 'session_not_active') {
        await _markEnded();
        return;
      }
      if (_phase == SessionPhase.starting) rethrow;
      _warning = 'Could not refresh the classroom code: ${e.message}';
      _tokenTimer = Timer(const Duration(seconds: 3), _refreshToken);
    }
    _notify();
  }

  Future<void> refreshRoster() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      _roster = await api.roster(id);
      _roster.sort((a, b) {
        if (a.isPresent != b.isPresent) return a.isPresent ? -1 : 1;
        return (a.rollNumber ?? a.fullName).compareTo(
          b.rollNumber ?? b.fullName,
        );
      });
    } on ApiException catch (e) {
      _warning = 'Roster did not update: ${e.message}';
    }
    _notify();
  }

  Future<String?> correct(RosterRow row, bool present, String reason) async {
    final id = _sessionId;
    if (id == null) return 'No session.';
    try {
      await api.correct(
        sessionId: id,
        studentId: row.studentId,
        present: present,
        reason: reason,
      );
      await refreshRoster();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<void> end() async {
    final id = _sessionId;
    if (id == null) return;
    _phase = SessionPhase.ending;
    _notify();
    try {
      _session = await api.endSession(id);
    } on ApiException catch (e) {
      if (e.code != 'session_already_ended') {
        _phase = SessionPhase.live;
        _warning = 'Could not end the session: ${e.message}';
        _notify();
        return;
      }
    }
    await _markEnded();
    await refreshRoster();
  }

  Future<void> _markEnded() async {
    _tokenTimer?.cancel();
    _rosterTimer?.cancel();
    await broadcaster.stop();
    await store.delete(_activeKey);
    _phase = SessionPhase.ended;
    _notify();
  }

  /// Download the server's CSV and save it in a temporary file to share.
  Future<File> exportCsv() async {
    final id = _sessionId!;
    final csv = await api.exportCsv(id);
    final dir = await getTemporaryDirectory();
    final safeName = classroom.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/attendance_${safeName}_$stamp.csv');
    return file.writeAsString(csv);
  }

  void _failWith(String message) {
    _tokenTimer?.cancel();
    _rosterTimer?.cancel();
    _error = message;
    _phase = SessionPhase.failed;
    broadcaster.stop();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tokenTimer?.cancel();
    _rosterTimer?.cancel();
    broadcaster.removeListener(notifyListeners);
    // Stop the radio first; the broadcaster notifies while stopping.
    broadcaster.stop().whenComplete(broadcaster.dispose);
    super.dispose();
  }
}

class _SessionError implements Exception {
  final String message;
  const _SessionError(this.message);
}
