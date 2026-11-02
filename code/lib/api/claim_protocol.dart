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

/// Size of the rotating session token (backend/app/tokens.py):
/// version (1) | session alias (4) | epoch (4) | HMAC tag (8).
const int tokenLength = 17;
const int tokenVersion = 1;

/// Parse lower or upper case hex into bytes. Throws [FormatException].
List<int> hexToBytes(String hex) {
  final clean = hex.trim();
  if (clean.length.isOdd) throw const FormatException('odd length hex');
  return [
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ];
}

/// True when [bytes] has the shape of a session token. Only the server can
/// tell whether it is genuine and fresh.
bool looksLikeToken(List<int> bytes) =>
    bytes.length == tokenLength && bytes.first == tokenVersion;

/// The 8 character room code both phones show: the token's session alias.
/// Students can compare it with the teacher's screen before checking in.
String roomCodeOf(List<int> token) =>
    bytesToHex(token.sublist(1, 5)).toUpperCase();
