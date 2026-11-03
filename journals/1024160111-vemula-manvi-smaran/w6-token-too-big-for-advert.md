# Week 6 : The Token Did Not Fit in the Advertisement

# Serving the Token Over GATT

## Error:

The server token is 17 bytes, but the teacher phone could
not put it in its Bluetooth advertisement. On iPhones it
could not send it at all.

## Relevant Context

A legacy BLE advertisement holds 31 bytes:

``` text
flags                3
128 bit service UUID 18
manufacturer data    10   (2 header + 2 id + 6 payload)
```

That leaves 6 bytes of payload on Android. iOS does not
allow manufacturer data in an advertisement at all.

## Key Observation

The advertisement only needs to say "a ClassLink teacher
is here". The token can travel another way once the
student has found the phone.

## Solution

The teacher phone advertises only the service UUID and
serves the token from a readable characteristic:

``` dart
GATTCharacteristic.mutable(
  uuid: BleConstants.tokenCharacteristicUuid,
  properties: [GATTCharacteristicProperty.read],
  permissions: [GATTCharacteristicPermission.read],
  descriptors: [],
);
```

The student phone connects for a moment, reads 17 bytes,
and disconnects. Signal strength still comes from the
advertisements.

**Because**

A GATT read is not limited to 31 bytes and works the same
on Android and iOS, so an iPhone can now be the teacher
phone too.
