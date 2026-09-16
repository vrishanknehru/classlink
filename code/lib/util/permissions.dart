import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

enum PermissionOutcome { granted, denied, permanentlyDenied }

class BlePermissions {
  BlePermissions._();

  // Android 12+ grants BLE work through the Bluetooth permissions alone, and
  // the manifest caps ACCESS_FINE_LOCATION at API 30 (`neverForLocation`), so
  // requesting location there is auto-denied. Location is therefore requested
  // separately and treated as best-effort for Android 11 and older.
  static const List<Permission> _teacherPermissions = [
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
  ];

  static const List<Permission> _studentPermissions = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ];

  // iOS has a single Bluetooth permission and does not need location for BLE.
  static const List<Permission> _iosPermissions = [Permission.bluetooth];

  static Future<PermissionOutcome> requestForTeacher() =>
      _requestForRole(_teacherPermissions);

  static Future<PermissionOutcome> requestForStudent() =>
      _requestForRole(_studentPermissions);

  static Future<PermissionOutcome> _requestForRole(
    List<Permission> androidPermissions,
  ) async {
    if (Platform.isIOS) return _request(_iosPermissions);
    final outcome = await _request(androidPermissions);
    if (outcome != PermissionOutcome.granted) return outcome;
    // Pre-Android 12 needs location for BLE scanning; on newer versions this
    // request is a no-op that must not block the session.
    await Permission.locationWhenInUse.request();
    return PermissionOutcome.granted;
  }

  static Future<PermissionOutcome> _request(List<Permission> permissions) async {
    final statuses = await permissions.request();
    if (statuses.values.every((status) => status.isGranted)) {
      return PermissionOutcome.granted;
    }
    if (statuses.values.any((status) => status.isPermanentlyDenied)) {
      return PermissionOutcome.permanentlyDenied;
    }
    return PermissionOutcome.denied;
  }
}
