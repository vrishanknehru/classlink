# Week 2 : Check In Blocked on Android 12 and Newer

# Bluetooth Permissions on Android 12+

## Error:

On newer Android phones the student check in never
started. The permission step reported a denial even after
the user tapped Allow.

## Relevant Context

The manifest declares the scan permission with the
`neverForLocation` flag, because the app only uses signal
strength and never works out a location:

``` xml
<uses-permission
    android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
```

but the app still required `ACCESS_FINE_LOCATION` before
scanning.

## Key Observation

With `neverForLocation` set, Android 12 and newer auto
deny the location request without showing a dialog. A
hard requirement on location therefore failed every time.

## Solution

Treat the Bluetooth permissions as the real requirement,
and ask for location only as a best effort for Android 11
and older:

``` dart
final outcome = await _request(androidPermissions);
if (outcome != PermissionOutcome.granted) return outcome;
// Pre Android 12 needs location for BLE scanning; on newer
// versions this request must not block the session.
await Permission.locationWhenInUse.request();
return PermissionOutcome.granted;
```

**Because**

From Android 12, Bluetooth scanning has its own runtime
permissions. Location is only needed on older versions, so
it cannot be a blocker on new ones.
