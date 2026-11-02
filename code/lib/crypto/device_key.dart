import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../util/secure_store.dart';
import 'der.dart';

/// The student's device key: ECDSA P-256 over SHA-256.
///
/// The server stores the public half when the phone binds (PUT /v1/devices/me)
/// and checks every attendance claim against it, so a claim cannot come from
/// another phone. The private half never leaves this phone: it sits in the
/// platform secure storage (iOS Keychain, Android Keystore backed storage).
class DeviceKey {
  static final ECDomainParameters _curve = ECCurve_secp256r1();

  final ECPrivateKey _private;
  final ECPublicKey _public;

  DeviceKey._(this._private, this._public);

  factory DeviceKey.fromPrivateScalar(BigInt d) {
    if (d <= BigInt.zero || d >= _curve.n) {
      throw ArgumentError('private scalar out of range');
    }
    final q = (_curve.G * d)!;
    return DeviceKey._(ECPrivateKey(d, _curve), ECPublicKey(q, _curve));
  }

  factory DeviceKey.fromPrivateHex(String hex) =>
      DeviceKey.fromPrivateScalar(BigInt.parse(hex, radix: 16));

  factory DeviceKey.generate() {
    final seed = Random.secure();
    final random = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(List.generate(32, (_) => seed.nextInt(256))),
        ),
      );
    final generator = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(_curve), random));
    final AsymmetricKeyPair<PublicKey, PrivateKey> pair = generator
        .generateKeyPair();
    return DeviceKey._(
      pair.privateKey as ECPrivateKey,
      pair.publicKey as ECPublicKey,
    );
  }

  /// Lower case hex of the private scalar, 64 characters. Storage only.
  String get privateHex =>
      bigIntToBytes(_private.d!, length: 32)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

  /// Base64 SubjectPublicKeyInfo DER, the format the server accepts.
  String get publicKeyBase64 =>
      base64.encode(p256SpkiFromPoint(_public.Q!.getEncoded(false)));

  /// Sign [message] (UTF-8) and return a base64 DER signature.
  ///
  /// Uses RFC 6979 deterministic nonces, so no random number is needed at
  /// signing time and the same input always gives the same signature.
  String signBase64(String message) {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(_private));
    final signature =
        signer.generateSignature(Uint8List.fromList(utf8.encode(message)))
            as ECSignature;
    return base64.encode(ecdsaSignatureToDer(signature.r, signature.s));
  }

  /// Check a base64 DER signature against this key. Used by tests.
  bool verifyBase64(String message, String signatureBase64) {
    try {
      final (r, s) = ecdsaSignatureFromDer(base64.decode(signatureBase64));
      final verifier = ECDSASigner(SHA256Digest())
        ..init(false, PublicKeyParameter<ECPublicKey>(_public));
      return verifier.verifySignature(
        Uint8List.fromList(utf8.encode(message)),
        ECSignature(r, s),
      );
    } on FormatException {
      return false;
    }
  }
}

/// Loads the device key from secure storage, creating it on first use.
class DeviceKeyStore {
  static const _keyName = 'classlink.device_key.v1';
  static const _boundPrefix = 'classlink.device_bound.';

  final SecureStore _store;
  DeviceKey? _cached;

  DeviceKeyStore(this._store);

  Future<DeviceKey> loadOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;
    final stored = await _store.read(_keyName);
    if (stored != null) {
      try {
        return _cached = DeviceKey.fromPrivateHex(stored);
      } on Object {
        // Corrupt entry: make a fresh key. The binding marker no longer
        // matches, so the app rebinds and the server revokes the old key.
      }
    }
    final key = DeviceKey.generate();
    await _store.write(_keyName, key.privateHex);
    return _cached = key;
  }

  /// Whether the server already holds [key] for [userId]. The marker stores
  /// the public key itself, so a new key on this phone reads as unbound.
  Future<bool> isBoundFor(String userId, DeviceKey key) async =>
      (await _store.read('$_boundPrefix$userId')) == key.publicKeyBase64;

  Future<void> markBoundFor(String userId, DeviceKey key) =>
      _store.write('$_boundPrefix$userId', key.publicKeyBase64);

  Future<void> forgetBindingFor(String userId) =>
      _store.delete('$_boundPrefix$userId');
}
