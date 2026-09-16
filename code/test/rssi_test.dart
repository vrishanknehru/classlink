import 'package:flutter_test/flutter_test.dart';
import 'package:ble_attendance_poc/util/rssi_math.dart';

void main() {
  group('medianRssi', () {
    test('returns the single value for one sample', () {
      expect(medianRssi([-70]), -70);
    });

    test('returns the middle value for an odd-length list', () {
      expect(medianRssi([-80, -70, -60]), -70);
    });

    test('averages the two middle values for an even-length list', () {
      expect(medianRssi([-80, -70, -60, -50]), -65);
    });

    test('is order-independent', () {
      expect(medianRssi([-60, -90, -70]), medianRssi([-90, -70, -60]));
    });

    test('throws on empty input', () {
      expect(() => medianRssi([]), throwsArgumentError);
    });
  });

  group('isWithinThreshold', () {
    test('true when rssi is stronger (less negative) than threshold', () {
      expect(isWithinThreshold(rssi: -60, thresholdDbm: -75), isTrue);
    });

    test('true when rssi equals the threshold', () {
      expect(isWithinThreshold(rssi: -75, thresholdDbm: -75), isTrue);
    });

    test('false when rssi is weaker (more negative) than threshold', () {
      expect(isWithinThreshold(rssi: -90, thresholdDbm: -75), isFalse);
    });
  });
}
