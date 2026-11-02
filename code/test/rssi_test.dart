import 'package:flutter_test/flutter_test.dart';
import 'package:classlink/util/rssi_math.dart';

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

  group('evaluateWindow', () {
    test('no samples is too few, with no median', () {
      expect(
        evaluateWindow([], thresholdDbm: -75, minSamples: 3),
        (WindowVerdict.tooFewSamples, null),
      );
    });

    test('fewer samples than the policy asks for is too few', () {
      expect(
        evaluateWindow([-60, -61], thresholdDbm: -75, minSamples: 3).$1,
        WindowVerdict.tooFewSamples,
      );
    });

    test('weak median is too far', () {
      expect(
        evaluateWindow([-80, -82, -79], thresholdDbm: -75, minSamples: 3),
        (WindowVerdict.tooFar, -80),
      );
    });

    test('strong enough and enough samples passes', () {
      expect(
        evaluateWindow([-70, -62, -75, -66], thresholdDbm: -75, minSamples: 3),
        (WindowVerdict.ok, -68),
      );
    });

    test('a median exactly on the threshold passes, like the server', () {
      expect(
        evaluateWindow([-75, -75, -75], thresholdDbm: -75, minSamples: 3).$1,
        WindowVerdict.ok,
      );
    });
  });
}
