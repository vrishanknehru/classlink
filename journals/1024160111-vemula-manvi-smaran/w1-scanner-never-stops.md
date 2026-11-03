# Week 1 : Check In Again Did Not Reset the Scanner

# Scanner Lifecycle

## Error:

In the prototype, tapping **Check In Again** after a
successful check in did nothing useful. On a second try
the student phone sometimes counted old signal readings,
and if no teacher was nearby the scan never stopped.

## Relevant Context

`StudentScanner.startScanning` subscribed to the BLE
streams every time it ran:

``` dart
_stateSub = _manager.stateChanged.listen(...);
_discoveredSub = _manager.discovered.listen(_onDiscovered);
```

and the window timer simply rescheduled itself while no
advertisement arrived:

``` dart
if (_samples.isEmpty) {
  _scheduleWindowEvaluation(name, rollNumber);
  return;
}
```

## Key Observation

Two things leaked between runs. The old stream
subscriptions stayed alive, so a second run had two
listeners feeding `_samples`. And nothing put a limit on
how long a scan could last.

## Solution

Cancel the old subscriptions before starting, and stop
after a fixed time:

``` dart
await _discoveredSub?.cancel();
await _stateSub?.cancel();
_scanStartedAt = DateTime.now();
```

``` dart
if (startedAt != null &&
    DateTime.now().difference(startedAt) > maxScanDuration) {
  await _timeOut();   // stops scanning, shows a message
  return;
}
```

with `maxScanDuration` set to 90 seconds.

**Because**

A Dart `StreamSubscription` keeps delivering events until
someone calls `cancel()`. Starting a new listen does not
replace the old one, it adds another.
