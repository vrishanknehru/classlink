# Week 4 : Cancel Did Nothing During a Long Wait

# Cancelling Async Steps

## Error:

Tapping **Cancel** while the app searched for a teacher
would have no effect until the 60 second search timed out.

## Relevant Context

The search waited on a future with a timeout:

``` dart
await firstSighting.future.timeout(_findTimeout);
```

so a cancel flag checked after that line is seen too late.

## Key Observation

A Dart `await` cannot be interrupted from outside. The
code only noticed the flag once the slow future finished.

## Solution

Race every long wait against a cancel signal:

``` dart
Future<T> _cancellable<T>(Future<T> future) async {
  final outcome = await Future.any<Object?>([
    future.then<Object?>((value) => _Value<T>(value)),
    _cancelSignal.future.then<Object?>((_) => null),
  ]);
  if (outcome is _Value<T>) return outcome.value;
  throw const _Cancelled();
}
```

`cancel()` completes `_cancelSignal`, so the wait ends at
once.

**Because**

`Future.any` completes with whichever future finishes
first. The slow future keeps running in the background,
but nothing waits on it any more.
