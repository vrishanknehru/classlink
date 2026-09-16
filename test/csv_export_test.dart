import 'package:flutter_test/flutter_test.dart';
import 'package:ble_attendance_poc/attendance/attendance_record.dart';
import 'package:ble_attendance_poc/attendance/csv_export.dart';

void main() {
  group('AttendanceCsvExport.toCsvString', () {
    test('includes a header row and one row per record', () {
      final csv = AttendanceCsvExport.toCsvString(
        classroomName: 'Room 101',
        sessionStartedAt: DateTime.utc(2026, 9, 15, 8, 0, 0),
        records: [
          AttendanceRecord(
            name: 'Ada Lovelace',
            rollNumber: '12',
            medianRssi: -68,
            checkedInAt: DateTime.utc(2026, 9, 15, 8, 1, 0),
          ),
          AttendanceRecord(
            name: 'Alan Turing',
            rollNumber: '7',
            medianRssi: -71,
            checkedInAt: DateTime.utc(2026, 9, 15, 8, 2, 0),
          ),
        ],
      );

      final lines = csv.trim().split('\r\n');
      expect(lines, hasLength(3));
      expect(
        lines[0],
        'Classroom,Session Start,Name,Roll Number,Median RSSI (dBm),Checked In At',
      );
      expect(lines[1], contains('Ada Lovelace'));
      expect(lines[1], contains('12'));
      expect(lines[1], contains('-68'));
      expect(lines[2], contains('Alan Turing'));
      expect(lines[2], contains('-71'));
    });

    test('produces only the header row when there are no records', () {
      final csv = AttendanceCsvExport.toCsvString(
        classroomName: 'Room 101',
        sessionStartedAt: DateTime.utc(2026, 9, 15, 8, 0, 0),
        records: const [],
      );

      final lines = csv.trim().split('\r\n');
      expect(lines, hasLength(1));
    });
  });
}
