# Week 3 : Student Phone Lost the Teacher Mid Check In

# Matching Readings to the Right Phone

## Error:

After reading the token, the student phone could wait
until the code expired, reporting too few readings, even
while standing next to the teacher.

## Relevant Context

The check in first finds the teacher phone, reads the
token, then scans again and keeps only readings from that
same phone:

``` dart
if (event.peripheral.uuid == teacher.uuid) {
  fromTeacher.add(event.rssi);
}
```

## Key Observation

Android may advertise from a new random address after a
connection or a restart of advertising. The phone was
still there, just under a different id, so every reading
was thrown away.

## Solution

Keep two lists. If the matched phone gives nothing for two
windows in a row, fall back to readings from any ClassLink
teacher in range:

``` dart
var batch = List<int>.of(fromTeacher);
if (batch.isEmpty) {
  emptyWindows++;
  if (emptyWindows >= 2) batch = List<int>.of(fromAnyTeacher);
}
```

**Because**

Bluetooth privacy rotates device addresses on purpose. The
scan already filters on the ClassLink service UUID, so any
reading it returns comes from a teacher phone.
