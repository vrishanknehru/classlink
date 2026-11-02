import 'dart:convert';

import 'package:classlink/auth/auth_service.dart';
import 'package:classlink/config.dart';
import 'package:classlink/util/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _jwt(Map<String, Object?> claims) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(claims)}.sig';
}

const _config = AppConfig(
  apiBaseUrl: 'https://api.test',
  supabaseUrl: 'https://sb.test',
  supabaseAnonKey: 'anon',
);

void main() {
  test('reads user id, email and expiry from a JWT', () {
    final s = AuthSession.fromJwt(
      _jwt({'sub': 'u1', 'email': 'a@b.c', 'exp': 1792065600}),
    );
    expect(s.userId, 'u1');
    expect(s.email, 'a@b.c');
    expect(s.expiresAt, DateTime.utc(2026, 10, 15, 12));
  });

  test('rejects things that are not JWTs', () {
    expect(() => AuthSession.fromJwt('nope'), throwsA(isA<AuthException>()));
    expect(
      () => AuthSession.fromJwt(_jwt({'email': 'x'})),
      throwsA(isA<AuthException>()),
    );
  });

  test('password sign in stores the session and survives a restart', () async {
    final store = MemoryStore();
    late http.Request seen;
    final access = _jwt({'sub': 'u1', 'email': 't@x.edu', 'exp': 4102444800});
    final auth = AuthService(
      _config,
      store,
      client: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({'access_token': access, 'refresh_token': 'r1'}),
          200,
        );
      }),
    );
    await auth.signIn(' t@x.edu ', 'secret1');
    expect(seen.url.toString(), 'https://sb.test/auth/v1/token?grant_type=password');
    expect(seen.headers['apikey'], 'anon');
    expect(jsonDecode(seen.body), {'email': 't@x.edu', 'password': 'secret1'});
    expect(await auth.validAccessToken(), access);

    final restored = AuthService(_config, store);
    await restored.restore();
    expect(restored.session?.userId, 'u1');
  });

  test('refreshes a token that is about to expire', () async {
    final now = DateTime.utc(2026, 10, 15, 12);
    final soon = now.add(const Duration(seconds: 30));
    final later = now.add(const Duration(hours: 1));
    final first = _jwt({'sub': 'u1', 'exp': soon.millisecondsSinceEpoch ~/ 1000});
    final second = _jwt({'sub': 'u1', 'exp': later.millisecondsSinceEpoch ~/ 1000});
    final calls = <String>[];
    final auth = AuthService(
      _config,
      MemoryStore(),
      now: () => now,
      client: MockClient((request) async {
        calls.add(request.url.query);
        final refreshing = request.url.query.contains('refresh_token');
        return http.Response(
          jsonEncode({
            'access_token': refreshing ? second : first,
            'refresh_token': refreshing ? 'r2' : 'r1',
          }),
          200,
        );
      }),
    );
    await auth.signIn('a@b.c', 'secret1');
    expect(await auth.validAccessToken(), second);
    expect(calls.last, 'grant_type=refresh_token');
    expect(auth.session?.refreshToken, 'r2');
  });

  test('shows the Supabase error message', () async {
    final auth = AuthService(
      _config,
      MemoryStore(),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'error_description': 'Invalid login credentials'}),
          400,
        ),
      ),
    );
    await expectLater(
      auth.signIn('a@b.c', 'wrongpw'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Invalid login credentials',
        ),
      ),
    );
    expect(auth.isSignedIn, isFalse);
  });

  test('developer token works without Supabase settings', () async {
    final auth = AuthService(
      const AppConfig(apiBaseUrl: 'x', supabaseUrl: '', supabaseAnonKey: ''),
      MemoryStore(),
    );
    await auth.useDeveloperToken(_jwt({'sub': 'dev', 'exp': 4102444800}));
    expect(auth.session?.userId, 'dev');
  });
}
