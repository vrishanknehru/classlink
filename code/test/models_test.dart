import 'package:classlink/api/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile reads the role and optional fields', () {
    final teacher = Profile.fromJson({
      'id': 'u1',
      'role': 'teacher',
      'full_name': 'Test Teacher',
      'roll_number': null,
      'email': 'teacher@thapar.edu',
    });
    expect(teacher.isTeacher, isTrue);
    expect(teacher.rollNumber, isNull);

    final student = Profile.fromJson({
      'id': 'u2',
      'role': 'student',
      'full_name': 'Mahi Singh',
      'roll_number': '1024160102',
    });
    expect(student.role, Role.student);
    expect(student.email, isNull);
  });

  test('classroom reads the join code', () {
    final c = Classroom.fromJson({
      'id': 'c1',
      'name': 'UCS503P',
      'join_code': 'ABC123',
    });
    expect(c.joinCode, 'ABC123');
  });

  test('session parses UTC times and knows when it is active', () {
    final json = {
      'id': 's1',
      'classroom_id': 'c1',
      'alias': 'a1b2c3d4',
      'rssi_threshold_dbm': -75,
      'sample_window_seconds': 4,
      'min_samples': 3,
      'started_at': '2026-11-26T09:00:00Z',
      'ended_at': null,
    };
    final live = SessionInfo.fromJson(json);
    expect(live.isActive, isTrue);
    expect(live.startedAt, DateTime.utc(2026, 11, 26, 9));
    expect(live.rssiThresholdDbm, -75);

    final ended = SessionInfo.fromJson({
      ...json,
      'ended_at': '2026-11-26T10:00:00Z',
    });
    expect(ended.isActive, isFalse);
    expect(ended.endedAt, DateTime.utc(2026, 11, 26, 10));
  });

  test('token reads its epoch, period and expiry', () {
    final t = SessionToken.fromJson({
      'token_hex': '00' * 17,
      'epoch': 117500000,
      'period_seconds': 15,
      'expires_at': '2026-11-26T09:00:15Z',
    });
    expect(t.epoch, 117500000);
    expect(t.periodSeconds, 15);
    expect(t.expiresAt, DateTime.utc(2026, 11, 26, 9, 0, 15));
  });

  test('claim result defaults duplicate_retry to false', () {
    final r = ClaimResult.fromJson({
      'attendance': {
        'session_id': 's1',
        'student_id': 'u2',
        'status': 'present',
        'source': 'ble_claim',
        'median_rssi': -61,
        'recorded_at': '2026-11-26T09:01:00Z',
      },
    });
    expect(r.duplicateRetry, isFalse);
    expect(r.attendance.medianRssi, -61);
    expect(r.attendance.status, 'present');
  });

  test('roster row without a record is absent and not manual', () {
    final none = RosterRow.fromJson({
      'student_id': 'u3',
      'full_name': 'Zed',
      'roll_number': null,
      'status': null,
      'source': null,
      'median_rssi': null,
      'recorded_at': null,
    });
    expect(none.isPresent, isFalse);
    expect(none.isManual, isFalse);
    expect(none.recordedAt, isNull);

    final fixed = RosterRow.fromJson({
      'student_id': 'u4',
      'full_name': 'Ada',
      'roll_number': '1024160120',
      'status': 'present',
      'source': 'manual_correction',
      'median_rssi': null,
      'recorded_at': '2026-11-26T09:05:00Z',
    });
    expect(fixed.isPresent, isTrue);
    expect(fixed.isManual, isTrue);
  });
}
