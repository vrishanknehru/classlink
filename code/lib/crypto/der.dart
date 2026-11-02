/// The two DER shapes the server expects. Kept pure so tests can pin them.
library;

import 'dart:typed_data';

/// SubjectPublicKeyInfo header for an id-ecPublicKey on prime256v1, followed
/// by a BIT STRING that holds a 65 byte uncompressed point.
const List<int> _p256SpkiPrefix = [
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, //
  0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
  0x42, 0x00,
];

/// Wrap an uncompressed P-256 point (0x04 | X | Y) as SubjectPublicKeyInfo DER.
Uint8List p256SpkiFromPoint(List<int> uncompressedPoint) {
  if (uncompressedPoint.length != 65 || uncompressedPoint.first != 0x04) {
    throw ArgumentError('expected a 65 byte uncompressed P-256 point');
  }
  return Uint8List.fromList([..._p256SpkiPrefix, ...uncompressedPoint]);
}

/// Unsigned big endian bytes of a non negative integer, at least one byte.
Uint8List bigIntToBytes(BigInt value, {int? length}) {
  if (value.isNegative) throw ArgumentError('negative value');
  final bytes = <int>[];
  var v = value;
  while (v > BigInt.zero) {
    bytes.insert(0, (v & BigInt.from(0xff)).toInt());
    v = v >> 8;
  }
  if (bytes.isEmpty) bytes.add(0);
  if (length != null) {
    if (bytes.length > length) throw ArgumentError('value too large');
    while (bytes.length < length) {
      bytes.insert(0, 0);
    }
  }
  return Uint8List.fromList(bytes);
}

BigInt bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b & 0xff);
  }
  return result;
}

List<int> _derInteger(BigInt value) {
  var body = bigIntToBytes(value).toList();
  if (body.first & 0x80 != 0) body = [0, ...body];
  return [0x02, body.length, ...body];
}

/// ECDSA signature as DER `SEQUENCE { INTEGER r, INTEGER s }`, the format that
/// Python `cryptography` and Java `SHA256withECDSA` use.
Uint8List ecdsaSignatureToDer(BigInt r, BigInt s) {
  final content = [..._derInteger(r), ..._derInteger(s)];
  return Uint8List.fromList([0x30, content.length, ...content]);
}

/// Inverse of [ecdsaSignatureToDer]. Throws [FormatException] on bad input.
(BigInt, BigInt) ecdsaSignatureFromDer(List<int> der) {
  var i = 0;
  int next() {
    if (i >= der.length) throw const FormatException('truncated signature');
    return der[i++];
  }

  BigInt readInteger() {
    if (next() != 0x02) throw const FormatException('expected INTEGER');
    final length = next();
    if (length == 0 || i + length > der.length) {
      throw const FormatException('bad INTEGER length');
    }
    final value = bytesToBigInt(der.sublist(i, i + length));
    i += length;
    return value;
  }

  if (next() != 0x30) throw const FormatException('expected SEQUENCE');
  final length = next();
  if (length != der.length - 2) throw const FormatException('bad length');
  final r = readInteger();
  final s = readInteger();
  if (i != der.length) throw const FormatException('trailing bytes');
  return (r, s);
}
