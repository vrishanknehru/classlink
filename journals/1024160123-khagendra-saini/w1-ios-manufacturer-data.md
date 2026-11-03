# Week 1 : Sending the Session Code From an iPhone

# Advertising on iOS

## Error:

An iPhone teacher advertised, but student phones never
saw the session code.

## Relevant Context

The prototype put the code in manufacturer data:

``` dart
manufacturerSpecificData: [
  ManufacturerSpecificData(
    id: BleConstants.manufacturerId,
    data: SessionCode.encode(_sessionCode!),
  ),
],
```

## Key Observation

iOS lets an app advertise only a local name and service
UUIDs. Manufacturer data is dropped without an error. On
Android the opposite care is needed: setting a name
renames the phone itself.

## Solution

Choose the field by platform:

``` dart
name: Platform.isIOS
    ? SessionCode.toAdvertisedName(_sessionCode!) // CL042917
    : null,
manufacturerSpecificData: Platform.isIOS ? [] : [...],
```

and let the scanner read either one:

``` dart
_detectedSessionCode =
    (matches.isNotEmpty ? SessionCode.decode(matches.first.data) : null) ??
    SessionCode.fromAdvertisedName(event.advertisement.name);
```

**Because**

One scanner that checks both places finds an Android or an
iPhone teacher without knowing which one it is.
