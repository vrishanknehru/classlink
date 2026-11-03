# Week 5 : An iPhone Could Not Share the Session Token

# Serving the Token Over GATT

## Error:

The server token is 17 bytes, and an iPhone teacher had
no way to put it in a Bluetooth advertisement. iOS only
lets apps advertise a name and service UUIDs, and a name
long enough for 17 bytes does not fit either.

## Relevant Context

A legacy BLE advertisement holds 31 bytes. The 128 bit
service UUID alone takes 18 of them. The earlier fix, the
code in the device name, worked for a 6 digit code but not
for a 17 byte signed token.

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

and answers each read with the latest token from the
server:

``` dart
await _manager.respondReadRequestWithValue(
  event.request,
  value: token.sublist(offset),
);
```

**Because**

A GATT read has no 31 byte limit and CoreBluetooth allows
it, so an iPhone can now be the teacher phone, the same as
an Android one.
