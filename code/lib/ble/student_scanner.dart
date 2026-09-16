import 'dart:async';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import '../util/rssi_math.dart';
import 'ble_constants.dart';

enum ScanState { idle, scanning, tooFar, connecting, checkedIn, failure }

/// Wraps [CentralManager] to scan for a classroom's advertisement, sample
/// RSSI over a short window, and — once within range — connect once to
/// write a check-in. Student-only central/scanner role — never relays to
/// other students (see `CLAUDE.md` rule #6, no mesh).
class StudentScanner extends ChangeNotifier {
  final CentralManager _manager = CentralManager();
  final int thresholdDbm;

  static const _sampleWindow = Duration(seconds: 4);

  StudentScanner({this.thresholdDbm = -75});

  ScanState _state = ScanState.idle;
  ScanState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int? _lastMedianRssi;
  int? get lastMedianRssi => _lastMedianRssi;

  String? _detectedSessionCode;
  String? get detectedSessionCode => _detectedSessionCode;

  StreamSubscription<DiscoveredEventArgs>? _discoveredSub;
  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>? _stateSub;
  Timer? _windowTimer;
  final List<int> _samples = [];
  Peripheral? _peripheral;

  Future<void> startScanning({
    required String name,
    required String rollNumber,
  }) async {
    if (_state == ScanState.scanning || _state == ScanState.connecting) {
      return;
    }
    _errorMessage = null;
    _lastMedianRssi = null;
    _samples.clear();
    _peripheral = null;
    _detectedSessionCode = null;
    _state = ScanState.scanning;
    notifyListeners();

    _stateSub = _manager.stateChanged.listen((event) async {
      if (event.state == BluetoothLowEnergyState.unauthorized &&
          Platform.isAndroid) {
        await _manager.authorize();
      }
    });
    _discoveredSub = _manager.discovered.listen(_onDiscovered);

    try {
      await waitForPoweredOn(_manager);
      await _manager.startDiscovery(serviceUUIDs: [BleConstants.serviceUuid]);
    } on BluetoothUnavailableException catch (e) {
      _errorMessage = e.message;
      _state = ScanState.failure;
      notifyListeners();
      return;
    } catch (e) {
      _errorMessage = 'Could not start scanning: $e';
      _state = ScanState.failure;
      notifyListeners();
      return;
    }

    _scheduleWindowEvaluation(name, rollNumber);
  }

  void _onDiscovered(DiscoveredEventArgs event) {
    _peripheral = event.peripheral;
    _samples.add(event.rssi);
    final matches = event.advertisement.manufacturerSpecificData.where(
      (d) => d.id == BleConstants.manufacturerId,
    );
    // Android teachers send the code as manufacturer data; iOS teachers can
    // only send it in the local name.
    _detectedSessionCode =
        (matches.isNotEmpty ? SessionCode.decode(matches.first.data) : null) ??
        SessionCode.fromAdvertisedName(event.advertisement.name) ??
        _detectedSessionCode;
    notifyListeners();
  }

  void _scheduleWindowEvaluation(String name, String rollNumber) {
    _windowTimer?.cancel();
    _windowTimer = Timer(
      _sampleWindow,
      () => _evaluateWindow(name, rollNumber),
    );
  }

  Future<void> _evaluateWindow(String name, String rollNumber) async {
    if (_state != ScanState.scanning && _state != ScanState.tooFar) {
      return; // Already moved on (connecting/checkedIn/failure/stopped).
    }
    if (_samples.isEmpty) {
      // No advertisement observed in this window yet; keep waiting.
      _scheduleWindowEvaluation(name, rollNumber);
      return;
    }

    final median = medianRssi(_samples);
    _lastMedianRssi = median;
    _samples.clear();

    if (!isWithinThreshold(rssi: median, thresholdDbm: thresholdDbm)) {
      _state = ScanState.tooFar;
      notifyListeners();
      _scheduleWindowEvaluation(name, rollNumber);
      return;
    }

    await _connectAndCheckIn(
      name: name,
      rollNumber: rollNumber,
      medianRssi: median,
    );
  }

  Future<void> _connectAndCheckIn({
    required String name,
    required String rollNumber,
    required int medianRssi,
  }) async {
    final peripheral = _peripheral;
    if (peripheral == null) return;
    _state = ScanState.connecting;
    notifyListeners();
    try {
      await _manager.stopDiscovery();
      await _manager.connect(peripheral);
      try {
        await _manager.requestMTU(peripheral, mtu: 200);
      } catch (_) {
        // Not fatal; falls back to the negotiated default MTU.
      }
      final services = await _manager.discoverGATT(peripheral);
      final service = services.firstWhere(
        (s) => s.uuid == BleConstants.serviceUuid,
      );
      final characteristic = service.characteristics.firstWhere(
        (c) => c.uuid == BleConstants.checkInCharacteristicUuid,
      );
      final payload = CheckInPayload(
        name: name,
        rollNumber: rollNumber,
        medianRssi: medianRssi,
        observedAt: DateTime.now(),
      );
      await _manager.writeCharacteristic(
        peripheral,
        characteristic,
        value: payload.encode(),
        type: GATTCharacteristicWriteType.withResponse,
      );
      await _manager.disconnect(peripheral);
      _state = ScanState.checkedIn;
    } catch (e) {
      _errorMessage = 'Check-in failed: $e';
      _state = ScanState.failure;
      try {
        await _manager.disconnect(peripheral);
      } catch (_) {
        // Already disconnected or never connected.
      }
    }
    notifyListeners();
  }

  Future<void> stopScanning() async {
    _windowTimer?.cancel();
    await _discoveredSub?.cancel();
    await _stateSub?.cancel();
    _discoveredSub = null;
    _stateSub = null;
    try {
      await _manager.stopDiscovery();
    } catch (_) {
      // Discovery may already be stopped.
    }
    _state = ScanState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _windowTimer?.cancel();
    _discoveredSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}
