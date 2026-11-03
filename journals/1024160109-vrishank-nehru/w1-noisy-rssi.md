# Week 1 : One Stray Reading Marked a Student Present

# Proximity From Signal Strength

## Error:

If the app trusted a single Bluetooth reading, a student
two rooms away could be marked present: one strong packet
would be enough to pass the distance check.

## Relevant Context

The simplest check compares each reading with the
threshold as soon as it arrives:

``` dart
if (event.rssi >= thresholdDbm) {
  // check in
}
```

## Key Observation

RSSI jumps by 10 dBm or more from one packet to the next
because of walls, bodies and reflections. A single packet
says very little about distance.

## Solution

Collect every reading over a 4 second window and decide
on the median:

``` dart
int medianRssi(List<int> samples) {
  final sorted = [...samples]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}
```

The server also asks for a minimum number of samples, 3
by default, so a window with one lucky packet fails.

**Because**

The median ignores outliers: one reading of −50 dBm among
readings near −85 dBm leaves the median near −85, while an
average would move.
