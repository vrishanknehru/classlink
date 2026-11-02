import 'dart:async';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/claim_protocol.dart';
import '../api/models.dart';
import '../ble/ble_constants.dart';
import '../crypto/device_key.dart';
import '../util/rssi_math.dart';

enum CheckInStep {
  idle,
  searching,
  readingCode,
  verifying,
  measuring,
  tooFar,
  submitting,
  done,
  failed,
}

/// The student side of SRS UC-1, end to end:
///
/// 1. Scan for a ClassLink teacher phone and pick the strongest one.
/// 2. Connect for a moment and read the current session token.
/// 3. Send the token to the server (challenge). The server checks it and
///    returns a one time nonce plus the session's signal policy.
/// 4. Sample signal strength for the policy window, waiting while the
///    student is too far away.
/// 5. Sign the claim with the device key and send it. The server decides.
class CheckInController extends ChangeNotifier {
  final ClassLinkApi api;
  final DeviceKeyStore keys;
  final CentralManager _central = CentralManager();

  CheckInController({required this.api, required this.keys});

  CheckInStep _step = CheckInStep.idle;
  CheckInStep get step => _step;

  String? _error;
  String? get error => _error;

  String? _roomCode;

  /// The 8 character code also shown on the teacher's screen.
  String? get roomCode => _roomCode;

  int? _lastMedian;
  int? get lastMedianRssi => _lastMedian;

  int? _threshold;
  int? get thresholdDbm => _threshold;

  ClaimResult? _result;
  ClaimResult? get result => _result;

  bool get isBusy =>
      _step != CheckInStep.idle &&
      _step != CheckInStep.done &&
      _step != CheckInStep.failed;

  bool _cancelled = false;
  bool _disposed = false;
  Completer<void> _cancelSignal = Completer<void>();
  StreamSubscription<DiscoveredEventArgs>? _discoverSub;
  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>? _stateSub;

  static const _maxAttempts = 3;
  static const _findTimeout = Duration(seconds: 60);
  static const _pickWindow = Duration(milliseconds: 1500);

  /// How long we keep trying with one nonce. The server keeps it for two
  /// minutes by default; this is measured on the phone's own clock so a
  /// wrong phone clock cannot make us overrun it.
  static const _nonceBudget = Duration(seconds: 90);

  Future<void> start() async {
    if (isBusy) return;
    _cancelled = false;
    _cancelSignal = Completer<void>();
    _error = null;
    _result = null;
    _roomCode = null;
    _lastMedian = null;
    _threshold = null;
    _set(CheckInStep.searching);
    _stateSub ??= _central.stateChanged.listen((event) async {
      if (event.state == BluetoothLowEnergyState.unauthorized &&
          Platform.isAndroid) {
        await _central.authorize();
      }
    });
    try {
      await waitForPoweredOn(_central);
      for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
        _set(CheckInStep.searching);
        final peripheral = await _findClassroom();
        _set(CheckInStep.readingCode);
        final token = await _readToken(peripheral);
        _roomCode = roomCodeOf(token);
        _set(CheckInStep.verifying);
        final challenge = await _cancellable(
          api.challenge(bytesToHex(token)),
        );
        _threshold = challenge.rssiThresholdDbm;
        final finished = await _measureAndClaim(peripheral, token, challenge);
        if (finished) return;
        // The nonce ran out while the student was too far; start over.
      }
      _fail('Could not get close enough in time. Move nearer and retry.');
    } on _Cancelled {
      _set(CheckInStep.idle);
    } on BluetoothUnavailableException catch (e) {
      _fail(e.message);
    } on ApiException catch (e) {
      _fail(e.message);
    } on _CheckInError catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Check in failed: $e');
    } finally {
      await _stopScan();
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    if (!_cancelSignal.isCompleted) _cancelSignal.complete();
    await _stopScan();
    _set(CheckInStep.idle);
  }

  void reset() {
    if (isBusy) return;
    _set(CheckInStep.idle);
  }

  // Step 1: find the strongest teacher phone nearby.
  Future<Peripheral> _findClassroom() async {
    final seen = <UUID, Peripheral>{};
    final samples = <UUID, List<int>>{};
    final firstSighting = Completer<void>();
    await _startScan((event) {
      final id = event.peripheral.uuid;
      seen[id] = event.peripheral;
      samples.putIfAbsent(id, () => []).add(event.rssi);
      if (!firstSighting.isCompleted) firstSighting.complete();
    });
    try {
      await _cancellable(firstSighting.future.timeout(_findTimeout));
    } on TimeoutException {
      throw const _CheckInError(
        'No classroom found. Ask the teacher to start the session, then retry.',
      );
    }
    // Give nearby rooms a moment to show up so we pick the closest teacher.
    await _cancellable(Future<void>.delayed(_pickWindow));
    await _stopScan();
    UUID? best;
    var bestMedian = -1000;
    for (final entry in samples.entries) {
      final m = medianRssi(entry.value);
      if (m > bestMedian) {
        bestMedian = m;
        best = entry.key;
      }
    }
    return seen[best]!;
  }

  // Step 2: connect for a moment and read the token characteristic.
  Future<List<int>> _readToken(Peripheral peripheral) async {
    Object? lastError;
    for (var tryNo = 0; tryNo < 2; tryNo++) {
      _checkCancelled();
      try {
        await _central
            .connect(peripheral)
            .timeout(const Duration(seconds: 10));
        final services = await _central
            .discoverGATT(peripheral)
            .timeout(const Duration(seconds: 10));
        final service = services.firstWhere(
          (s) => s.uuid == BleConstants.serviceUuid,
        );
        final characteristic = service.characteristics.firstWhere(
          (c) => c.uuid == BleConstants.tokenCharacteristicUuid,
        );
        final value = await _central
            .readCharacteristic(peripheral, characteristic)
            .timeout(const Duration(seconds: 10));
        if (!looksLikeToken(value)) {
          throw const _CheckInError(
            'The teacher phone is not sharing a session code yet. Retry.',
          );
        }
        return value.toList();
      } on _CheckInError {
        rethrow;
      } catch (e) {
        lastError = e;
      } finally {
        try {
          await _central.disconnect(peripheral);
        } catch (_) {
          // Already disconnected.
        }
      }
    }
    throw _CheckInError('Could not read the classroom code ($lastError).');
  }

  // Steps 4 and 5. Returns false when the nonce ran out before the student
  // got close enough, so the caller starts again with a fresh token.
  Future<bool> _measureAndClaim(
    Peripheral teacher,
    List<int> token,
    Challenge challenge,
  ) async {
    final window = Duration(seconds: challenge.sampleWindowSeconds);
    final deadline = DateTime.now().add(_nonceBudget);
    final fromTeacher = <int>[];
    final fromAnyTeacher = <int>[];
    var emptyWindows = 0;
    await _startScan((event) {
      fromAnyTeacher.add(event.rssi);
      if (event.peripheral.uuid == teacher.uuid) fromTeacher.add(event.rssi);
    });
    _set(CheckInStep.measuring);
    while (DateTime.now().add(window).isBefore(deadline)) {
      fromTeacher.clear();
      fromAnyTeacher.clear();
      await _cancellable(Future<void>.delayed(window));
      // Android can change the advertiser's address between scans. If the
      // phone we read from seems gone, use any ClassLink teacher in range.
      var batch = List<int>.of(fromTeacher);
      if (batch.isEmpty) {
        emptyWindows++;
        if (emptyWindows >= 2) batch = List<int>.of(fromAnyTeacher);
      }
      final (verdict, median) = evaluateWindow(
        batch,
        thresholdDbm: challenge.rssiThresholdDbm,
        minSamples: challenge.minSamples,
      );
      if (median != null) _lastMedian = median;
      if (verdict == WindowVerdict.tooFar) {
        _set(CheckInStep.tooFar);
        continue;
      }
      if (verdict == WindowVerdict.tooFewSamples) {
        _set(CheckInStep.measuring);
        continue;
      }
      await _stopScan();
      await _submit(token, challenge, median!, batch.length);
      return true;
    }
    await _stopScan();
    return false;
  }

  Future<void> _submit(
    List<int> token,
    Challenge challenge,
    int median,
    int sampleCount,
  ) async {
    _set(CheckInStep.submitting);
    final key = await keys.loadOrCreate();
    final observedAt = DateTime.now().toUtc();
    final message = canonicalClaim(
      sessionId: challenge.sessionId,
      nonce: challenge.nonce,
      token: token,
      medianRssi: median,
      sampleCount: sampleCount,
      observedAt: observedAt,
    );
    final signature = key.signBase64(message);
    // The server answers a repeated claim from its stored record, so a
    // network failure is safe to retry with the exact same body.
    for (var tryNo = 0; ; tryNo++) {
      try {
        _result = await api.claim(
          nonce: challenge.nonce,
          tokenHex: bytesToHex(token),
          medianRssi: median,
          sampleCount: sampleCount,
          observedAt: observedAt,
          signatureBase64: signature,
        );
        _set(CheckInStep.done);
        return;
      } on ApiException catch (e) {
        if (!e.isNetwork || tryNo >= 2) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 + tryNo));
      }
    }
  }

  Future<void> _startScan(void Function(DiscoveredEventArgs) onEvent) async {
    await _discoverSub?.cancel();
    _discoverSub = _central.discovered.listen(onEvent);
    await _central.startDiscovery(serviceUUIDs: [BleConstants.serviceUuid]);
  }

  Future<void> _stopScan() async {
    await _discoverSub?.cancel();
    _discoverSub = null;
    try {
      await _central.stopDiscovery();
    } catch (_) {
      // Not scanning.
    }
  }

  /// Wait for [future], but stop at once with [_Cancelled] if the student
  /// taps Cancel.
  Future<T> _cancellable<T>(Future<T> future) async {
    _checkCancelled();
    final outcome = await Future.any<Object?>([
      future.then<Object?>((value) => _Value<T>(value)),
      _cancelSignal.future.then<Object?>((_) => null),
    ]);
    if (outcome is _Value<T>) return outcome.value;
    throw const _Cancelled();
  }

  void _checkCancelled() {
    if (_cancelled) throw const _Cancelled();
  }

  void _fail(String message) {
    _error = message;
    _set(CheckInStep.failed);
  }

  void _set(CheckInStep step) {
    if (_disposed) return;
    if (_cancelled && step != CheckInStep.idle) return;
    _step = step;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelled = true;
    if (!_cancelSignal.isCompleted) _cancelSignal.complete();
    _discoverSub?.cancel();
    _stateSub?.cancel();
    _central.stopDiscovery().catchError((_) {});
    super.dispose();
  }
}

class _Value<T> {
  final T value;
  const _Value(this.value);
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _CheckInError implements Exception {
  final String message;
  const _CheckInError(this.message);
}
