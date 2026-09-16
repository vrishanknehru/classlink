/// RSSI sampling helpers. Kept free of Flutter/BLE imports so they're easy
/// to unit test in isolation.
int medianRssi(List<int> samples) {
  if (samples.isEmpty) {
    throw ArgumentError('samples must not be empty');
  }
  final sorted = [...samples]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  // Average the two middle values, rounding toward zero like a dBm reading.
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}

bool isWithinThreshold({required int rssi, required int thresholdDbm}) {
  // RSSI is negative; "closer" means a larger (less negative) value.
  return rssi >= thresholdDbm;
}
