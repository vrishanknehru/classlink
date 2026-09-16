import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// Shared BLE identifiers for the ClassLink proof-of-concept.
///
/// This is a POC protocol only — no rotating tokens, no signing, no
/// server validation. See `CLAUDE.md` for the full production contract
/// this is a thin slice of.
class BleConstants {
  BleConstants._();

  static final UUID serviceUuid = UUID.fromString(
    '7a1e9b30-2f44-4c7a-9d0e-1f8a6b2c3d4e',
  );

  static final UUID checkInCharacteristicUuid = UUID.fromString(
    '7a1e9b31-2f44-4c7a-9d0e-1f8a6b2c3d4e',
  );

  /// Arbitrary id used to carry the session code in the advertisement's
  /// manufacturer-specific data. Not a registered Bluetooth SIG company id —
  /// fine for a local proof-of-concept, not for production use.
  static const int manufacturerId = 0x2e19;
}

/// The short numeric code shown on the teacher's screen and carried in the
/// advertisement, so a student can visually confirm they're about to check
/// in to the right classroom before connecting.
class SessionCode {
  SessionCode._();

  static final Random _random = Random();

  static String generate() {
    final value = _random.nextInt(1000000);
    return value.toString().padLeft(6, '0');
  }

  static Uint8List encode(String code) =>
      Uint8List.fromList(utf8.encode(code));

  static String? decode(Uint8List bytes) {
    try {
      return _validate(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  /// iOS peripherals can only advertise a local name and service UUIDs, so an
  /// iPhone teacher carries the code in the name as `CL<code>` instead of in
  /// manufacturer-specific data.
  static const String namePrefix = 'CL';

  static String toAdvertisedName(String code) => '$namePrefix$code';

  static String? fromAdvertisedName(String? name) {
    if (name == null || !name.startsWith(namePrefix)) return null;
    return _validate(name.substring(namePrefix.length));
  }

  static String? _validate(String code) =>
      RegExp(r'^\d{6}$').hasMatch(code) ? code : null;
}

/// The payload a student writes to the teacher's check-in characteristic
/// once it has confirmed proximity via RSSI sampling.
class CheckInPayload {
  final String name;
  final String rollNumber;
  final int medianRssi;
  final DateTime observedAt;

  CheckInPayload({
    required this.name,
    required this.rollNumber,
    required this.medianRssi,
    required this.observedAt,
  });

  Uint8List encode() {
    final json = jsonEncode({
      'n': name,
      'r': rollNumber,
      'rssi': medianRssi,
      't': observedAt.toIso8601String(),
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  static CheckInPayload? decode(Uint8List bytes) {
    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return CheckInPayload(
        name: map['n'] as String,
        rollNumber: map['r'] as String,
        medianRssi: map['rssi'] as int,
        observedAt: DateTime.parse(map['t'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

class BluetoothUnavailableException implements Exception {
  final String message;
  const BluetoothUnavailableException(this.message);

  @override
  String toString() => message;
}

/// CoreBluetooth rejects peripheral/central commands issued before the
/// manager reports `poweredOn`, and on a fresh launch it starts as `unknown`.
Future<void> waitForPoweredOn(
  BluetoothLowEnergyManager manager, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  var state = manager.state;
  if (state == BluetoothLowEnergyState.unknown) {
    try {
      state = await manager.stateChanged
          .map((event) => event.state)
          .firstWhere((s) => s != BluetoothLowEnergyState.unknown)
          .timeout(timeout);
    } on TimeoutException {
      state = manager.state;
    }
  }
  switch (state) {
    case BluetoothLowEnergyState.poweredOn:
      return;
    case BluetoothLowEnergyState.poweredOff:
      throw const BluetoothUnavailableException(
        'Bluetooth is off. Turn it on in Settings or Control Centre and try again.',
      );
    case BluetoothLowEnergyState.unauthorized:
      throw const BluetoothUnavailableException(
        'ClassLink is not allowed to use Bluetooth. Enable it in Settings > ClassLink.',
      );
    case BluetoothLowEnergyState.unsupported:
      throw const BluetoothUnavailableException(
        'This device does not support Bluetooth Low Energy.',
      );
    case BluetoothLowEnergyState.unknown:
      throw const BluetoothUnavailableException(
        'Bluetooth did not become ready. Toggle Bluetooth off and on, then retry.',
      );
  }
}
