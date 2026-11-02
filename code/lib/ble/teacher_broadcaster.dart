import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import 'ble_constants.dart';

enum BroadcastState { idle, starting, broadcasting, failure }

/// Teacher phone as a BLE peripheral: advertises the ClassLink service and
/// answers reads of the token characteristic with whatever token the server
/// issued last. The phone never makes tokens itself; it only relays them.
class TeacherBroadcaster extends ChangeNotifier {
  final PeripheralManager _manager = PeripheralManager();

  BroadcastState _state = BroadcastState.idle;
  BroadcastState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Uint8List? _token;

  int _readsServed = 0;

  /// How many times a student phone has read the token this session.
  int get readsServed => _readsServed;

  StreamSubscription<GATTCharacteristicReadRequestedEventArgs>? _readSub;
  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>? _stateSub;

  TeacherBroadcaster() {
    _stateSub = _manager.stateChanged.listen((event) async {
      if (event.state == BluetoothLowEnergyState.unauthorized &&
          Platform.isAndroid) {
        await _manager.authorize();
      }
    });
  }

  /// Replace the token served to students. Call this whenever the server
  /// rotates it.
  void updateToken(List<int> token) {
    _token = Uint8List.fromList(token);
  }

  Future<void> start() async {
    if (_state == BroadcastState.broadcasting ||
        _state == BroadcastState.starting) {
      return;
    }
    _state = BroadcastState.starting;
    _errorMessage = null;
    _readsServed = 0;
    notifyListeners();
    try {
      await waitForPoweredOn(_manager);
      await _manager.removeAllServices();
      final tokenCharacteristic = GATTCharacteristic.mutable(
        uuid: BleConstants.tokenCharacteristicUuid,
        properties: [GATTCharacteristicProperty.read],
        permissions: [GATTCharacteristicPermission.read],
        descriptors: [],
      );
      await _manager.addService(
        GATTService(
          uuid: BleConstants.serviceUuid,
          isPrimary: true,
          includedServices: [],
          characteristics: [tokenCharacteristic],
        ),
      );
      _readSub ??= _manager.characteristicReadRequested.listen(_onRead);
      // Service UUID only: it fits a legacy advertisement on both platforms,
      // and leaving the name out stops the plugin renaming an Android phone.
      await _manager.startAdvertising(
        Advertisement(serviceUUIDs: [BleConstants.serviceUuid]),
      );
      _state = BroadcastState.broadcasting;
    } on BluetoothUnavailableException catch (e) {
      _state = BroadcastState.failure;
      _errorMessage = e.message;
    } catch (e) {
      _state = BroadcastState.failure;
      _errorMessage = 'Could not start Bluetooth: $e';
    }
    notifyListeners();
  }

  Future<void> _onRead(GATTCharacteristicReadRequestedEventArgs event) async {
    if (event.characteristic.uuid != BleConstants.tokenCharacteristicUuid) {
      await _manager.respondReadRequestWithError(
        event.request,
        error: GATTError.attributeNotFound,
      );
      return;
    }
    final token = _token;
    if (token == null) {
      await _manager.respondReadRequestWithError(
        event.request,
        error: GATTError.readNotPermitted,
      );
      return;
    }
    final offset = event.request.offset;
    if (offset > token.length) {
      await _manager.respondReadRequestWithError(
        event.request,
        error: GATTError.invalidOffset,
      );
      return;
    }
    await _manager.respondReadRequestWithValue(
      event.request,
      value: token.sublist(offset),
    );
    if (offset == 0) {
      _readsServed++;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _token = null;
    try {
      await _manager.stopAdvertising();
      await _manager.removeAllServices();
    } catch (_) {
      // Best effort; the session is ending regardless.
    }
    _state = BroadcastState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _readSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}
