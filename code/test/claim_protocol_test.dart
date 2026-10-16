import 'package:ble_attendance_poc/api/claim_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('golden vector matches the backend', () {
    final token = <int>[
      0x01, 0x01, 0x02, 0x03, 0x04, 0x00, 0x00, 0x00, 0xf1, //
      0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6, 0x07, 0x08,
    ];
    final message = canonicalClaim(
      sessionId: '11111111-2222-3333-4444-555555555555',
      nonce: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      token: token,
      medianRssi: -62,
      sampleCount: 5,
      observedAt: DateTime.utc(2026, 10, 15, 12),
    );
    expect(
      message,
      'classlink-claim-v1\n'
      '11111111-2222-3333-4444-555555555555\n'
      'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n'
      '0101020304000000f1a1b2c3d4e5f60708\n'
      '-62\n5\n1792065600',
    );
  });

  test('sub second noise does not change the signed time', () {
    String at(DateTime t) => canonicalClaim(
          sessionId: 's',
          nonce: 'n',
          token: const [1],
          medianRssi: -60,
          sampleCount: 5,
          observedAt: t,
        );
    final base = DateTime.utc(2026, 10, 15, 12);
    expect(at(base.add(const Duration(milliseconds: 900))), at(base));
    expect(at(base.add(const Duration(seconds: 1))), isNot(at(base)));
  });
}
