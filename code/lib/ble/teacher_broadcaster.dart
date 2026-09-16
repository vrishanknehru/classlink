import 'dart:async';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import '../attendance/attendance_record.dart';
import 'ble_constants.dart';

enum BroadcastState { idle, starting, advertising, stopping, failure }

/// Wraps [PeripheralManager] to advertise a classroom session and collect
/// check-ins written by student devices. Teacher-only advertiser role —
/// see `CLAUDE.md` rule #6: no mesh, no student-to-student relaying.
class TeacherBroadcaster extends ChangeNotifier {
  final PeripheralManager _manager = PeripheralManager();

  BroadcastState _state = BroadcastState.idle;
  BroadcastState get state => _state;

  String? _sessionCode;
  String? get sessionCode => _sessionCode;

  DateTime? _sessionStartedAt;
  DateTime? get sessionStartedAt => _sessionStartedAt;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final List<AttendanceRecord> _records = [];
  List<AttendanceRecord> get records => List.unmodifiable(_records);
  final Set<String> _seenRollNumbers = {};

  StreamSubscription<GATTCharacteristicWriteRequestedEventArgs>? _writeSub;
  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>? _stateSub;

  TeacherBroadcaster() {
    _stateSub = _manager.stateChanged.listen((event) async {
      if (event.state == BluetoothLowEnergyState.unauthorized &&
          Platform.isAndroid) {
        await _manager.authorize();
      }
    });
  }

  Future<void> startSession() async {
    if (_state == BroadcastState.advertising ||
        _state == BroadcastState.starting) {
      return;
    }
    _state = BroadcastState.starting;
    _errorMessage = null;
    notifyListeners();
    try {
      await waitForPoweredOn(_manager);
      await _manager.removeAllServices();

      final checkInCharacteristic = GATTCharacteristic.mutable(
        uuid: BleConstants.checkInCharacteristicUuid,
        properties: [GATTCharacteristicProperty.write],
        permissions: [GATTCharacteristicPermission.write],
        descriptors: [],
      );

      final service = GATTService(
        uuid: BleConstants.serviceUuid,
        isPrimary: true,
        includedServices: [],
        characteristics: [checkInCharacteristic],
      );

      await _manager.addService(service);

      _writeSub ??= _manager.characteristicWriteRequested.listen(
        _onWriteRequested,
      );

      _sessionCode = SessionCode.generate();
      _sessionStartedAt = DateTime.now();
      _records.clear();
      _seenRollNumbers.clear();

      // Legacy advertisements are capped at 31 bytes: flags (3) + 128-bit
      // service UUID (18) + manufacturer data (10) fills it exactly on Android,
      // so no name there (the plugin would also rename the phone). iOS drops
      // manufacturer data, so the code travels in the local name instead.
      final advertisement = Advertisement(
        serviceUUIDs: [BleConstants.serviceUuid],
        name: Platform.isIOS ? SessionCode.toAdvertisedName(_sessionCode!) : null,
        manufacturerSpecificData: Platform.isIOS
            ? []
            : [
                ManufacturerSpecificData(
                  id: BleConstants.manufacturerId,
                  data: SessionCode.encode(_sessionCode!),
                ),
              ],
      );
      await _manager.startAdvertising(advertisement);

      _state = BroadcastState.advertising;
    } on BluetoothUnavailableException catch (e) {
      _state = BroadcastState.failure;
      _errorMessage = e.message;
    } catch (e) {
      _state = BroadcastState.failure;
      _errorMessage = 'Could not start broadcasting: $e';
    }
    notifyListeners();
  }

  Future<void> _onWriteRequested(
    GATTCharacteristicWriteRequestedEventArgs event,
  ) async {
    final payload = CheckInPayload.decode(event.request.value);
    await _manager.respondWriteRequest(event.request);
    if (payload == null) return;
    if (_seenRollNumbers.contains(payload.rollNumber)) {
      return; // One attendance record per student per session.
    }
    _seenRollNumbers.add(payload.rollNumber);
    _records.add(
      AttendanceRecord(
        name: payload.name,
        rollNumber: payload.rollNumber,
        medianRssi: payload.medianRssi,
        checkedInAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<void> endSession() async {
    if (_state != BroadcastState.advertising) return;
    _state = BroadcastState.stopping;
    notifyListeners();
    try {
      await _manager.stopAdvertising();
      await _manager.removeAllServices();
    } catch (_) {
      // Best-effort cleanup; the session is ending regardless.
    }
    _state = BroadcastState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _writeSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}
