/// Shapes returned by the ClassLink API (see backend/app/schemas.py).
library;

DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String);

enum Role { teacher, student }

class Profile {
  final String id;
  final Role role;
  final String fullName;
  final String? rollNumber;
  final String? email;

  const Profile({
    required this.id,
    required this.role,
    required this.fullName,
    required this.rollNumber,
    required this.email,
  });

  bool get isTeacher => role == Role.teacher;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    role: j['role'] == 'teacher' ? Role.teacher : Role.student,
    fullName: j['full_name'] as String,
    rollNumber: j['roll_number'] as String?,
    email: j['email'] as String?,
  );
}

class Classroom {
  final String id;
  final String name;
  final String joinCode;

  const Classroom({
    required this.id,
    required this.name,
    required this.joinCode,
  });

  factory Classroom.fromJson(Map<String, dynamic> j) => Classroom(
    id: j['id'] as String,
    name: j['name'] as String,
    joinCode: j['join_code'] as String,
  );
}

class SessionInfo {
  final String id;
  final String classroomId;
  final String alias;
  final int rssiThresholdDbm;
  final int sampleWindowSeconds;
  final int minSamples;
  final DateTime startedAt;
  final DateTime? endedAt;

  const SessionInfo({
    required this.id,
    required this.classroomId,
    required this.alias,
    required this.rssiThresholdDbm,
    required this.sampleWindowSeconds,
    required this.minSamples,
    required this.startedAt,
    required this.endedAt,
  });

  bool get isActive => endedAt == null;

  factory SessionInfo.fromJson(Map<String, dynamic> j) => SessionInfo(
    id: j['id'] as String,
    classroomId: j['classroom_id'] as String,
    alias: j['alias'] as String,
    rssiThresholdDbm: j['rssi_threshold_dbm'] as int,
    sampleWindowSeconds: j['sample_window_seconds'] as int,
    minSamples: j['min_samples'] as int,
    startedAt: _time(j['started_at'])!,
    endedAt: _time(j['ended_at']),
  );
}

class SessionToken {
  final String tokenHex;
  final int epoch;
  final int periodSeconds;
  final DateTime expiresAt;

  const SessionToken({
    required this.tokenHex,
    required this.epoch,
    required this.periodSeconds,
    required this.expiresAt,
  });

  factory SessionToken.fromJson(Map<String, dynamic> j) => SessionToken(
    tokenHex: j['token_hex'] as String,
    epoch: j['epoch'] as int,
    periodSeconds: j['period_seconds'] as int,
    expiresAt: _time(j['expires_at'])!,
  );
}

class Challenge {
  final String nonce;
  final String sessionId;
  final int rssiThresholdDbm;
  final int sampleWindowSeconds;
  final int minSamples;
  final DateTime expiresAt;

  const Challenge({
    required this.nonce,
    required this.sessionId,
    required this.rssiThresholdDbm,
    required this.sampleWindowSeconds,
    required this.minSamples,
    required this.expiresAt,
  });

  factory Challenge.fromJson(Map<String, dynamic> j) => Challenge(
    nonce: j['nonce'] as String,
    sessionId: j['session_id'] as String,
    rssiThresholdDbm: j['rssi_threshold_dbm'] as int,
    sampleWindowSeconds: j['sample_window_seconds'] as int,
    minSamples: j['min_samples'] as int,
    expiresAt: _time(j['expires_at'])!,
  );
}

class AttendanceRecord {
  final String sessionId;
  final String studentId;
  final String status;
  final String source;
  final int? medianRssi;
  final DateTime recordedAt;

  const AttendanceRecord({
    required this.sessionId,
    required this.studentId,
    required this.status,
    required this.source,
    required this.medianRssi,
    required this.recordedAt,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
    sessionId: j['session_id'] as String,
    studentId: j['student_id'] as String,
    status: j['status'] as String,
    source: j['source'] as String,
    medianRssi: j['median_rssi'] as int?,
    recordedAt: _time(j['recorded_at'])!,
  );
}

class ClaimResult {
  final bool duplicateRetry;
  final AttendanceRecord attendance;

  const ClaimResult({required this.duplicateRetry, required this.attendance});

  factory ClaimResult.fromJson(Map<String, dynamic> j) => ClaimResult(
    duplicateRetry: j['duplicate_retry'] as bool? ?? false,
    attendance: AttendanceRecord.fromJson(
      j['attendance'] as Map<String, dynamic>,
    ),
  );
}

class RosterRow {
  final String studentId;
  final String fullName;
  final String? rollNumber;
  final String? status;
  final String? source;
  final int? medianRssi;
  final DateTime? recordedAt;

  const RosterRow({
    required this.studentId,
    required this.fullName,
    required this.rollNumber,
    required this.status,
    required this.source,
    required this.medianRssi,
    required this.recordedAt,
  });

  bool get isPresent => status == 'present';
  bool get isManual => source == 'manual_correction';

  factory RosterRow.fromJson(Map<String, dynamic> j) => RosterRow(
    studentId: j['student_id'] as String,
    fullName: j['full_name'] as String,
    rollNumber: j['roll_number'] as String?,
    status: j['status'] as String?,
    source: j['source'] as String?,
    medianRssi: j['median_rssi'] as int?,
    recordedAt: _time(j['recorded_at']),
  );
}
