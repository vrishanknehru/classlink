/// Wire format shared with the ClassLink backend (see SRS FR-ATT-03).
///
/// This file is pure Dart so the exact bytes the phone signs can be tested
/// without a device. The backend asserts the same golden vector in
/// backend/tests/test_crypto.py.
library;

const String claimDomain = 'classlink-claim-v1';

/// Lower case hex, two digits per byte.
String bytesToHex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// The string that the device key signs. Fields are joined with newlines and
/// the observation time is whole Unix seconds (sub second noise would break
/// the signature otherwise).
String canonicalClaim({
  required String sessionId,
  required String nonce,
  required List<int> token,
  required int medianRssi,
  required int sampleCount,
  required DateTime observedAt,
}) {
  final seconds = observedAt.toUtc().millisecondsSinceEpoch ~/ 1000;
  return [
    claimDomain,
    sessionId.toLowerCase(),
    nonce.toLowerCase(),
    bytesToHex(token),
    medianRssi.toString(),
    sampleCount.toString(),
    seconds.toString(),
  ].join('\n');
}
