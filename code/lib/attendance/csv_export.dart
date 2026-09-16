import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'attendance_record.dart';

class AttendanceCsvExport {
  AttendanceCsvExport._();

  static List<List<Object?>> _rows({
    required String classroomName,
    required DateTime sessionStartedAt,
    required List<AttendanceRecord> records,
  }) {
    final rows = <List<Object?>>[
      [
        'Classroom',
        'Session Start',
        'Name',
        'Roll Number',
        'Median RSSI (dBm)',
        'Checked In At',
      ],
    ];
    for (final record in records) {
      rows.add([
        classroomName,
        sessionStartedAt.toIso8601String(),
        record.name,
        record.rollNumber,
        record.medianRssi,
        record.checkedInAt.toIso8601String(),
      ]);
    }
    return rows;
  }

  static String toCsvString({
    required String classroomName,
    required DateTime sessionStartedAt,
    required List<AttendanceRecord> records,
  }) {
    final rows = _rows(
      classroomName: classroomName,
      sessionStartedAt: sessionStartedAt,
      records: records,
    );
    return const ListToCsvConverter().convert(rows);
  }

  static String _fileNameFor({
    required String classroomName,
    required DateTime sessionStartedAt,
  }) {
    final safeName = classroomName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final timestamp = sessionStartedAt
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    return 'attendance_${safeName}_$timestamp.csv';
  }

  static Future<File> saveToFile({
    required String classroomName,
    required DateTime sessionStartedAt,
    required List<AttendanceRecord> records,
  }) async {
    final csv = toCsvString(
      classroomName: classroomName,
      sessionStartedAt: sessionStartedAt,
      records: records,
    );
    final dir = await getApplicationDocumentsDirectory();
    final fileName = _fileNameFor(
      classroomName: classroomName,
      sessionStartedAt: sessionStartedAt,
    );
    final file = File('${dir.path}/$fileName');
    return file.writeAsString(csv);
  }

  static Future<void> share(File file, {required String classroomName}) {
    return Share.shareXFiles(
      [XFile(file.path)],
      text: 'Attendance export for $classroomName',
    );
  }
}
