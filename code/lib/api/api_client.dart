import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import 'models.dart';

/// An error from the ClassLink API, with the server's machine readable code
/// (for example `not_enrolled` or `teacher_only`) and a sentence to show.
class ApiException implements Exception {
  final int statusCode;
  final String code;

  const ApiException(this.statusCode, this.code);

  /// True for the 409 attendance rejections listed in SRS section 4.
  bool get isRejection => statusCode == 409;

  /// True when the request never got an answer (offline, timeout).
  bool get isNetwork => statusCode == 0;

  String get message => friendlyMessage(code);

  @override
  String toString() => message;
}

String friendlyMessage(String code) {
  switch (code) {
    case 'network_error':
      return 'Could not reach the ClassLink server. Check your internet and retry.';
    case 'signed_out':
      return 'Your sign in expired. Please sign in again.';
    case 'invalid_token':
      return 'That classroom signal is not valid. Move closer and retry.';
    case 'token_expired':
      return 'The classroom code changed while checking in. Retry.';
    case 'session_not_active':
      return 'This class session is not running.';
    case 'not_enrolled':
      return 'You have not joined this classroom. Join it with the code first.';
    case 'no_device_bound':
      return 'This phone is not registered to your account. Sign out and in again.';
    case 'challenge_unknown':
    case 'challenge_expired':
    case 'token_mismatch':
    case 'nonce_reused':
      return 'The check in took too long. Retry.';
    case 'claim_stale':
      return 'Your phone clock looks wrong. Set it to automatic time and retry.';
    case 'too_few_samples':
      return 'Not enough Bluetooth readings. Stay still near the teacher and retry.';
    case 'rssi_below_threshold':
      return 'You look too far from the teacher. Move closer and retry.';
    case 'bad_signature':
      return 'This phone\'s key does not match your account. Sign out and in again.';
    case 'duplicate':
      return 'You are already marked for this session.';
    case 'profile_required':
      return 'Finish setting up your profile first.';
    case 'teacher_only':
      return 'Only teachers can do that.';
    case 'student_only':
      return 'Only students can do that.';
    case 'roll_number_required':
      return 'Students need a roll number.';
    case 'unknown_join_code':
      return 'No classroom has that join code.';
    case 'active_session_exists':
      return 'This classroom already has a session running.';
    case 'session_not_found':
    case 'classroom_not_found':
      return 'Not found, or it belongs to another teacher.';
    case 'session_already_ended':
      return 'This session has already ended.';
    case 'student_not_enrolled':
      return 'That student is not in this classroom.';
    case 'invalid_public_key':
      return 'The server rejected this phone\'s key.';
    default:
      return 'Something went wrong ($code).';
  }
}

/// Typed calls for every route the app uses. [tokenProvider] returns the
/// current bearer token, refreshing it if needed, or null when signed out.
class ClassLinkApi {
  final String baseUrl;
  final Future<String?> Function() tokenProvider;
  final http.Client _http;
  final Duration timeout;

  ClassLinkApi({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _http = client ?? http.Client();

  // Accounts.

  Future<Profile> me() async => Profile.fromJson(await _get('/v1/me'));

  Future<Profile> createProfile({
    required String fullName,
    String? rollNumber,
  }) async => Profile.fromJson(
    await _send('POST', '/v1/profile', {
      'full_name': fullName,
      if (rollNumber != null && rollNumber.isNotEmpty)
        'roll_number': rollNumber,
    }),
  );

  Future<List<Classroom>> classrooms() async =>
      (await _getList('/v1/classrooms')).map(Classroom.fromJson).toList();

  Future<Classroom> createClassroom(String name) async =>
      Classroom.fromJson(await _send('POST', '/v1/classrooms', {'name': name}));

  Future<Classroom> joinClassroom(String joinCode) async => Classroom.fromJson(
    await _send('POST', '/v1/classrooms/join', {'join_code': joinCode}),
  );

  Future<void> bindDevice({
    required String publicKeyBase64,
    String? label,
  }) async {
    await _send('PUT', '/v1/devices/me', {
      'public_key': publicKeyBase64,
      'label': label,
    });
  }

  // Teacher.

  Future<SessionInfo> startSession(String classroomId) async =>
      SessionInfo.fromJson(
        await _send('POST', '/v1/sessions', {'classroom_id': classroomId}),
      );

  Future<SessionInfo> endSession(String sessionId) async =>
      SessionInfo.fromJson(
        await _send('POST', '/v1/sessions/$sessionId/end', const {}),
      );

  Future<SessionToken> currentToken(String sessionId) async =>
      SessionToken.fromJson(await _get('/v1/sessions/$sessionId/token'));

  Future<List<RosterRow>> roster(String sessionId) async =>
      (await _getList(
        '/v1/sessions/$sessionId/roster',
      )).map(RosterRow.fromJson).toList();

  Future<AttendanceRecord> correct({
    required String sessionId,
    required String studentId,
    required bool present,
    required String reason,
  }) async => AttendanceRecord.fromJson(
    await _send('POST', '/v1/sessions/$sessionId/corrections', {
      'student_id': studentId,
      'status': present ? 'present' : 'absent',
      'reason': reason,
    }),
  );

  Future<String> exportCsv(String sessionId) async {
    final response = await _raw('GET', '/v1/sessions/$sessionId/export.csv');
    return utf8.decode(response.bodyBytes);
  }

  // Student.

  Future<Challenge> challenge(String tokenHex) async => Challenge.fromJson(
    await _send('POST', '/v1/attendance/challenge', {'token_hex': tokenHex}),
  );

  Future<ClaimResult> claim({
    required String nonce,
    required String tokenHex,
    required int medianRssi,
    required int sampleCount,
    required DateTime observedAt,
    required String signatureBase64,
  }) async => ClaimResult.fromJson(
    await _send('POST', '/v1/attendance/claim', {
      'nonce': nonce,
      'token_hex': tokenHex,
      'median_rssi': medianRssi,
      'sample_count': sampleCount,
      // Whole seconds, matching the signed message exactly.
      'observed_at': DateTime.fromMillisecondsSinceEpoch(
        observedAt.toUtc().millisecondsSinceEpoch ~/ 1000 * 1000,
        isUtc: true,
      ).toIso8601String(),
      'signature': signatureBase64,
    }),
  );

  // Plumbing.

  Future<Map<String, dynamic>> _get(String path) async =>
      _decodeObject(await _raw('GET', path));

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final decoded = jsonDecode((await _raw('GET', path)).body);
    return (decoded as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, Object?> body,
  ) async => _decodeObject(await _raw(method, path, body));

  Map<String, dynamic> _decodeObject(http.Response r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  Future<http.Response> _raw(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final token = await tokenProvider();
    if (token == null) throw const ApiException(401, 'signed_out');
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(0, 'network_error');
    } on SocketException {
      throw const ApiException(0, 'network_error');
    } on http.ClientException {
      throw const ApiException(0, 'network_error');
    }
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, errorCode(response));
    }
    return response;
  }
}

/// Pull the machine readable code out of a FastAPI error body:
/// `{"detail": "teacher_only"}` or
/// `{"detail": {"status": "rejected", "reason": "not_enrolled"}}`.
String errorCode(http.Response response) {
  try {
    final body = jsonDecode(response.body);
    if (body is Map) {
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is Map && detail['reason'] is String) {
        return detail['reason'] as String;
      }
      if (detail is List) return 'invalid_request';
    }
  } on FormatException {
    // Not JSON; fall through.
  }
  if (response.statusCode == 401) return 'signed_out';
  return 'http_${response.statusCode}';
}
