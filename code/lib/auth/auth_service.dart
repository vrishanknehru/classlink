import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../util/secure_store.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// A signed in user as far as the phone knows. The server checks the token
/// on every call; nothing here is trusted by the backend.
class AuthSession {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String userId;
  final String? email;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
  });

  bool expiresWithin(Duration margin, DateTime now) {
    final at = expiresAt;
    return at != null && now.add(margin).isAfter(at);
  }

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'user_id': userId,
    'email': email,
  };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String?,
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.parse(json['expires_at'] as String),
    userId: json['user_id'] as String,
    email: json['email'] as String?,
  );

  /// Build a session from a raw JWT, reading `sub`, `email` and `exp`.
  factory AuthSession.fromJwt(String jwt, {String? refreshToken}) {
    final claims = decodeJwtPayload(jwt);
    final sub = claims['sub'];
    if (sub is! String || sub.isEmpty) {
      throw const AuthException('That token has no user id (sub).');
    }
    final exp = claims['exp'];
    return AuthSession(
      accessToken: jwt,
      refreshToken: refreshToken,
      expiresAt: exp is num
          ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true)
          : null,
      userId: sub,
      email: claims['email'] is String ? claims['email'] as String : null,
    );
  }
}

/// Reads the middle part of a JWT without checking the signature. The phone
/// only uses this to learn its own user id; the server does the real check.
Map<String, dynamic> decodeJwtPayload(String jwt) {
  final parts = jwt.trim().split('.');
  if (parts.length != 3) throw const AuthException('That is not a JWT.');
  try {
    final normalized = base64Url.normalize(parts[1]);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // Handled below.
  }
  throw const AuthException('Could not read that token.');
}

/// Email and password sign in through Supabase Auth's REST API, plus a
/// developer route that accepts a ready made JWT for the local stack.
class AuthService extends ChangeNotifier {
  static const _storageKey = 'classlink.auth_session.v1';

  final AppConfig config;
  final SecureStore _store;
  final http.Client _http;
  final DateTime Function() _now;

  AuthSession? _session;
  AuthSession? get session => _session;
  bool get isSignedIn => _session != null;

  AuthService(
    this.config,
    this._store, {
    http.Client? client,
    DateTime Function()? now,
  }) : _http = client ?? http.Client(),
       _now = now ?? DateTime.now;

  Future<void> restore() async {
    final raw = await _store.read(_storageKey);
    if (raw == null) return;
    try {
      _session = AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      await _store.delete(_storageKey);
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    final body = await _supabase('/auth/v1/token?grant_type=password', {
      'email': email.trim(),
      'password': password,
    });
    await _save(_sessionFromSupabase(body));
  }

  /// Returns true when Supabase wants the user to confirm their email first.
  Future<bool> signUp(String email, String password) async {
    final body = await _supabase('/auth/v1/signup', {
      'email': email.trim(),
      'password': password,
    });
    if (body['access_token'] is String) {
      await _save(_sessionFromSupabase(body));
      return false;
    }
    return true;
  }

  Future<void> useDeveloperToken(String jwt) async {
    await _save(AuthSession.fromJwt(jwt.trim()));
  }

  /// A token that is good for at least the next minute, refreshing it when
  /// needed. Returns null (and signs out) when the session cannot be saved.
  Future<String?> validAccessToken() async {
    final session = _session;
    if (session == null) return null;
    if (!session.expiresWithin(const Duration(seconds: 60), _now())) {
      return session.accessToken;
    }
    final refresh = session.refreshToken;
    if (refresh == null || !config.hasSupabase) {
      if (session.expiresWithin(Duration.zero, _now())) {
        await signOut();
        return null;
      }
      return session.accessToken;
    }
    try {
      final body = await _supabase('/auth/v1/token?grant_type=refresh_token', {
        'refresh_token': refresh,
      });
      final next = _sessionFromSupabase(body);
      await _save(next);
      return next.accessToken;
    } on AuthException {
      await signOut();
      return null;
    }
  }

  Future<void> signOut() async {
    _session = null;
    await _store.delete(_storageKey);
    notifyListeners();
  }

  Future<void> _save(AuthSession session) async {
    _session = session;
    await _store.write(_storageKey, jsonEncode(session.toJson()));
    notifyListeners();
  }

  AuthSession _sessionFromSupabase(Map<String, dynamic> body) {
    final access = body['access_token'];
    if (access is! String) {
      throw const AuthException('Sign in did not return a session.');
    }
    final fromJwt = AuthSession.fromJwt(
      access,
      refreshToken: body['refresh_token'] as String?,
    );
    return fromJwt;
  }

  Future<Map<String, dynamic>> _supabase(
    String path,
    Map<String, Object?> payload,
  ) async {
    if (!config.hasSupabase) {
      throw const AuthException(
        'This build has no Supabase settings. Use a developer token.',
      );
    }
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('${config.supabaseUrl}$path'),
            headers: {
              'apikey': config.supabaseAnonKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw const AuthException('Could not reach the sign in server.');
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on Object {
      body = {};
    }
    if (response.statusCode >= 400) {
      final message =
          body['error_description'] ??
          body['msg'] ??
          body['message'] ??
          body['error'] ??
          'Sign in failed (${response.statusCode}).';
      throw AuthException(message.toString());
    }
    return body;
  }
}
