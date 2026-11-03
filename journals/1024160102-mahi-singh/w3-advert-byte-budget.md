# Week 3 : Making Sure the Advertisement Fits

# Testing a Hard Size Limit

## Error:

A change to the advertisement could push it over the BLE
size limit, and the phone would then fail to advertise at
runtime with no clear message.

## Relevant Context

A legacy advertisement holds 31 bytes. On Android the
prototype used:

``` text
flags                3
128 bit service UUID 18
manufacturer data    10
total                31
```

## Key Observation

The budget was exactly full, so any extra byte would
break it, and nothing checked it before a device test.

## Solution

Added a unit test so the build fails first:

``` dart
test('fits a legacy Android advertisement', () {
  const flags = 3;
  const serviceUuid128 = 2 + 16;
  final manufacturerData = 2 + 2 + SessionCode.encode('999999').length;
  expect(flags + serviceUuid128 + manufacturerData,
      lessThanOrEqualTo(31));
});
```

The prototype ended with 16 unit tests, all passing.

**Because**

A cheap test that runs on every push catches a size
mistake long before anyone carries two phones into a
classroom.
