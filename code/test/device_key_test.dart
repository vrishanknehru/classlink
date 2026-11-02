import 'dart:convert';

import 'package:classlink/api/claim_protocol.dart';
import 'package:classlink/crypto/der.dart';
import 'package:classlink/crypto/device_key.dart';
import 'package:classlink/util/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

// Vectors made with Python `cryptography`, the library the server verifies
// with. The private key is the RFC 6979 A.2.5 test key.
const _privateHex =
    'c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721';
const _publicSpki =
    'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEYP7UuiVanTHJYet0xjVtaMBJuJI7Yfps5mliLmDyn7Z5A/4QCLi8maQa6elWKLxk8vGyDC1+n1F3o8KU1EYimQ==';
// deterministic_signing=True over the golden claim in claim_protocol_test.
const _pythonSignature =
    'MEQCIFLk06DXNiG3TkCnqxBsjo4WDRki3A28dlU5042i7/S7AiBJS62XeWOmnuNStq6jt2Rq6YxAXheUcag6ImTpbxRrKg==';

String _goldenClaim() => canonicalClaim(
  sessionId: '11111111-2222-3333-4444-555555555555',
  nonce: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  token: hexToBytes('0101020304000000f1a1b2c3d4e5f60708'),
  medianRssi: -62,
  sampleCount: 5,
  observedAt: DateTime.utc(2026, 10, 15, 12),
);

void main() {
  final key = DeviceKey.fromPrivateHex(_privateHex);

  test('public key exports as the same SPKI DER the server parses', () {
    expect(key.publicKeyBase64, _publicSpki);
  });

  test('signature matches Python byte for byte (RFC 6979)', () {
    expect(key.signBase64(_goldenClaim()), _pythonSignature);
  });

  test('a signature made by Python verifies here', () {
    expect(key.verifyBase64(_goldenClaim(), _pythonSignature), isTrue);
    expect(key.verifyBase64('${_goldenClaim()}x', _pythonSignature), isFalse);
  });

  test('RFC 6979 A.2.5 known answer for "sample"', () {
    final der = base64.decode(key.signBase64('sample'));
    final (r, s) = ecdsaSignatureFromDer(der);
    expect(
      r.toRadixString(16),
      'efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716',
    );
    expect(
      s.toRadixString(16),
      'f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8',
    );
  });

  test('generated keys sign and verify, and differ each time', () {
    final a = DeviceKey.generate();
    final b = DeviceKey.generate();
    expect(a.privateHex, hasLength(64));
    expect(a.publicKeyBase64, isNot(b.publicKeyBase64));
    final sig = a.signBase64('hello');
    expect(a.verifyBase64('hello', sig), isTrue);
    expect(b.verifyBase64('hello', sig), isFalse);
    expect(DeviceKey.fromPrivateHex(a.privateHex).publicKeyBase64,
        a.publicKeyBase64);
  });

  test('rejects out of range private keys', () {
    expect(() => DeviceKey.fromPrivateScalar(BigInt.zero), throwsArgumentError);
  });

  group('DeviceKeyStore', () {
    test('creates once and then reuses the stored key', () async {
      final store = MemoryStore();
      final first = await DeviceKeyStore(store).loadOrCreate();
      final again = await DeviceKeyStore(store).loadOrCreate();
      expect(again.publicKeyBase64, first.publicKeyBase64);
    });

    test('binding marker follows the key and the user', () async {
      final store = MemoryStore();
      final keys = DeviceKeyStore(store);
      final key = await keys.loadOrCreate();
      expect(await keys.isBoundFor('u1', key), isFalse);
      await keys.markBoundFor('u1', key);
      expect(await keys.isBoundFor('u1', key), isTrue);
      expect(await keys.isBoundFor('u2', key), isFalse);
      expect(await keys.isBoundFor('u1', DeviceKey.generate()), isFalse);
      await keys.forgetBindingFor('u1');
      expect(await keys.isBoundFor('u1', key), isFalse);
    });

    test('replaces a corrupt stored key', () async {
      final store = MemoryStore()..values['classlink.device_key.v1'] = 'zz';
      final key = await DeviceKeyStore(store).loadOrCreate();
      expect(store.values['classlink.device_key.v1'], key.privateHex);
    });
  });
}
