import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// Shared BLE identifiers.
///
/// The teacher phone advertises [serviceUuid] and serves the current session
/// token from [tokenCharacteristicUuid]. A 17 byte token does not fit in a
/// legacy advertisement next to a 128 bit service UUID, and iOS will not put
/// manufacturer data in an advertisement at all, so the student phone
/// connects briefly and reads it. This works the same on Android and iOS.
class BleConstants {
  BleConstants._();

  static final UUID serviceUuid = UUID.fromString(
    '7a1e9b30-2f44-4c7a-9d0e-1f8a6b2c3d4e',
  );

  static final UUID tokenCharacteristicUuid = UUID.fromString(
    '7a1e9b32-2f44-4c7a-9d0e-1f8a6b2c3d4e',
  );
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
