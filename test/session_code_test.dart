import 'dart:typed_data';

import 'package:ble_attendance_poc/ble/ble_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionCode', () {
    test('round-trips through manufacturer data bytes', () {
      expect(SessionCode.decode(SessionCode.encode('042917')), '042917');
    });

    test('rejects malformed manufacturer data', () {
      expect(SessionCode.decode(Uint8List.fromList([0xff, 0xfe])), isNull);
      expect(SessionCode.decode(SessionCode.encode('12345')), isNull);
      expect(SessionCode.decode(SessionCode.encode('12a456')), isNull);
    });

    test('round-trips through the iOS advertised name', () {
      final name = SessionCode.toAdvertisedName('000123');
      expect(name, 'CL000123');
      expect(SessionCode.fromAdvertisedName(name), '000123');
    });

    test('ignores unrelated or malformed advertised names', () {
      expect(SessionCode.fromAdvertisedName(null), isNull);
      expect(SessionCode.fromAdvertisedName('ClassLink'), isNull);
      expect(SessionCode.fromAdvertisedName('JBL Flip 5'), isNull);
      expect(SessionCode.fromAdvertisedName('CL12345'), isNull);
      expect(SessionCode.fromAdvertisedName('CL1234567'), isNull);
    });

    test('fits a legacy Android advertisement with the service UUID', () {
      const flags = 3;
      const serviceUuid128 = 2 + 16;
      final manufacturerData = 2 + 2 + SessionCode.encode('999999').length;
      expect(flags + serviceUuid128 + manufacturerData, lessThanOrEqualTo(31));
    });
  });
}
