# Week 2 : Wireless Debugging Kept Dropping the iPhone

# Installing Test Builds on iPhone

## Error:

`flutter run` over Wi Fi to the iPhone kept losing the
connection, so test runs stopped halfway.

## Relevant Context

Testing needs the app installed and running on a real
phone, since BLE peripheral mode does not work in the
simulator.

## Key Observation

The debugger connection was the unstable part, not the
app. A release build does not need a debugger attached.

## Solution

Build in release mode and install it with Apple's device
tool:

``` shell
flutter build ios --release
xcrun devicectl device install app \
  --device <device-id> build/ios/iphoneos/Runner.app
```

For Android, build the release APK and sideload it:

``` shell
flutter build apk --release
```

The Android release APK came to 45 MB.

**Because**

A release build runs on its own on the phone, so a
dropped Wi Fi link no longer ends the test.
