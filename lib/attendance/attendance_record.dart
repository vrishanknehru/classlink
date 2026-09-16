class AttendanceRecord {
  final String name;
  final String rollNumber;
  final int medianRssi;
  final DateTime checkedInAt;

  const AttendanceRecord({
    required this.name,
    required this.rollNumber,
    required this.medianRssi,
    required this.checkedInAt,
  });
}
