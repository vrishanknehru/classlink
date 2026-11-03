# Week 2 : Bluetooth Calls Failed Right After Launch on iPhone

# Waiting for CoreBluetooth

## Error:

On a fresh launch the iPhone could fail to start scanning
or advertising, because the app sent Bluetooth commands
before the phone's Bluetooth was ready.

## Relevant Context

The app called the BLE manager as soon as the screen
opened:

``` dart
await _manager.startAdvertising(advertisement);
```

## Key Observation

CoreBluetooth starts in the `unknown` state and only later
reports `poweredOn`. It rejects commands sent before that.

## Solution

Wait for the state to settle, with a timeout, and give a
clear message for each problem:

``` dart
Future<void> waitForPoweredOn(BluetoothLowEnergyManager m) async {
  var state = m.state;
  if (state == BluetoothLowEnergyState.unknown) {
    state = await m.stateChanged
        .map((e) => e.state)
        .firstWhere((s) => s != BluetoothLowEnergyState.unknown)
        .timeout(const Duration(seconds: 5));
  }
  if (state == BluetoothLowEnergyState.poweredOff) {
    throw const BluetoothUnavailableException(
      'Bluetooth is off. Turn it on in Settings or Control Centre and try again.');
  }
  // unauthorized and unsupported get their own messages
}
```

**Because**

The Bluetooth stack powers up asynchronously. Waiting for
the state event is the only reliable way to know it is
ready.
