import 'dart:convert';

import 'package:classlink/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ClassLinkApi _api(MockClientHandler handler, {String? token = 'tok'}) =>
    ClassLinkApi(
      baseUrl: 'https://api.test',
      tokenProvider: () async => token,
      client: MockClient(handler),
    );

void main() {
  test('sends the bearer token and parses the challenge', () async {
    late http.Request seen;
    final api = _api((request) async {
      seen = request;
      return http.Response(
        jsonEncode({
          'nonce': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
          'session_id': '11111111-2222-3333-4444-555555555555',
          'rssi_threshold_dbm': -75,
          'sample_window_seconds': 4,
          'min_samples': 3,
          'expires_at': '2026-10-15T12:02:00Z',
        }),
        200,
      );
    });
    final c = await api.challenge('0101');
    expect(seen.method, 'POST');
    expect(seen.url.toString(), 'https://api.test/v1/attendance/challenge');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(seen.body), {'token_hex': '0101'});
    expect(c.minSamples, 3);
    expect(c.expiresAt, DateTime.utc(2026, 10, 15, 12, 2));
  });

  test('a 409 rejection surfaces its reason code', () async {
    final api = _api(
      (_) async => http.Response(
        jsonEncode({
          'detail': {'status': 'rejected', 'reason': 'not_enrolled'},
        }),
        409,
      ),
    );
    await expectLater(
      api.challenge('00'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'not_enrolled')
            .having((e) => e.isRejection, 'isRejection', isTrue),
      ),
    );
  });

  test('a plain detail string becomes the code', () async {
    final api = _api(
      (_) async => http.Response(jsonEncode({'detail': 'teacher_only'}), 403),
    );
    await expectLater(
      api.startSession('x'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'teacher_only')),
    );
  });

  test('claim sends whole second time that matches the signed text', () async {
    late Map<String, dynamic> body;
    final api = _api((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'status': 'accepted',
          'duplicate_retry': false,
          'attendance': {
            'session_id': 's',
            'student_id': 'u',
            'status': 'present',
            'source': 'ble_claim',
            'median_rssi': -62,
            'recorded_at': '2026-10-15T12:00:01Z',
          },
        }),
        200,
      );
    });
    final result = await api.claim(
      nonce: 'n',
      tokenHex: 'ab',
      medianRssi: -62,
      sampleCount: 5,
      observedAt: DateTime.utc(2026, 10, 15, 12, 0, 0, 900),
      signatureBase64: 'c2ln',
    );
    expect(body['observed_at'], '2026-10-15T12:00:00.000Z');
    expect(body['median_rssi'], -62);
    expect(body['signature'], 'c2ln');
    expect(result.attendance.status, 'present');
  });

  test('no token means signed out, without calling the server', () async {
    var called = false;
    final api = _api((_) async {
      called = true;
      return http.Response('{}', 200);
    }, token: null);
    await expectLater(
      api.me(),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'signed_out')),
    );
    expect(called, isFalse);
  });

  test('network failures are reported as such', () async {
    final api = _api((_) async => throw http.ClientException('offline'));
    await expectLater(
      api.me(),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)),
    );
  });

  test('every rejection reason has its own message', () {
    const reasons = [
      'invalid_token', 'token_expired', 'session_not_active', 'not_enrolled',
      'no_device_bound', 'challenge_unknown', 'challenge_expired',
      'nonce_reused', 'token_mismatch', 'claim_stale', 'too_few_samples',
      'rssi_below_threshold', 'bad_signature', 'duplicate',
    ];
    for (final r in reasons) {
      expect(friendlyMessage(r), isNot(contains('Something went wrong')), reason: r);
    }
  });
}
