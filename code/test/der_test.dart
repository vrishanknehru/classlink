import 'package:classlink/crypto/der.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('integers with the top bit set get a leading zero', () {
    final der = ecdsaSignatureToDer(BigInt.from(0x80), BigInt.from(1));
    expect(der, [0x30, 0x07, 0x02, 0x02, 0x00, 0x80, 0x02, 0x01, 0x01]);
    expect(ecdsaSignatureFromDer(der), (BigInt.from(0x80), BigInt.one));
  });

  test('round trips 256 bit values', () {
    final r = BigInt.parse('f' * 64, radix: 16);
    final s = BigInt.parse('7${'0' * 63}', radix: 16);
    expect(ecdsaSignatureFromDer(ecdsaSignatureToDer(r, s)), (r, s));
  });

  test('rejects malformed DER', () {
    expect(() => ecdsaSignatureFromDer([0x31, 0x00]), throwsFormatException);
    expect(() => ecdsaSignatureFromDer([0x30, 0x05, 0x02]),
        throwsFormatException);
  });

  test('SPKI wrapper needs an uncompressed point', () {
    expect(() => p256SpkiFromPoint(List.filled(65, 0)), throwsArgumentError);
    expect(p256SpkiFromPoint([4, ...List.filled(64, 1)]), hasLength(91));
  });

  test('fixed width big endian encoding', () {
    expect(bigIntToBytes(BigInt.from(258), length: 4), [0, 0, 1, 2]);
    expect(bigIntToBytes(BigInt.zero), [0]);
  });
}
