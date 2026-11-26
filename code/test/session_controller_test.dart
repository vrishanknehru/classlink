import 'dart:convert';

import 'package:classlink/api/api_client.dart';
import 'package:classlink/api/models.dart';
import 'package:classlink/ble/teacher_broadcaster.dart';
import 'package:classlink/teacher/session_controller.dart';
import 'package:classlink/util/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _classroom = Classroom(id: 'room-1', name: 'UCS503P', joinCode: 'ABC123');
const _activeKey = 'classlink.active_session.room-1';

Map<String, Object?> _session(String id, {String? endedAt}) => {
  'id': id,
  'classroom_id': _classroom.id,
  'alias': 'a1b2c3d4',
  'rssi_threshold_dbm': -75,
  'sample_window_seconds': 4,
  'min_samples': 3,
  'started_at': '2026-11-26T09:00:00Z',
  'ended_at': endedAt,
};

Map<String, Object?> _row(String name, String? roll, String? status) => {
  'student_id': 'id-$name',
  'full_name': name,
  'roll_number': roll,
  'status': status,
  'source': status == null ? null : 'ble_claim',
  'median_rssi': status == null ? null : -60,
  'recorded_at': status == null ? null : '2026-11-26T09:01:00Z',
};

final _token = {
  'token_hex': '01a1b2c3d400000001${'ab' * 8}',
  'epoch': 1,
  'period_seconds': 15,
  'expires_at': '2099-01-01T00:00:30Z',
};

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

http.Response _error(String code, int status) =>
    _json({'detail': code}, status);

class FakeBroadcaster extends TokenBroadcaster {
  FakeBroadcaster({this.fails = false});

  final bool fails;
  BroadcastState _state = BroadcastState.idle;
  List<int>? lastToken;
  int stops = 0;

  @override
  BroadcastState get state => _state;

  @override
  String? get errorMessage => fails ? 'Bluetooth is off.' : null;

  @override
  int get readsServed => 0;

  @override
  void updateToken(List<int> token) => lastToken = token;

  @override
  Future<void> start() async {
    _state = fails ? BroadcastState.failure : BroadcastState.broadcasting;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stops++;
    _state = BroadcastState.idle;
    notifyListeners();
  }
}

/// A fake server. [routes] maps "METHOD path" to a response; every request is
/// recorded in [calls].
class FakeServer {
  FakeServer(this.routes);

  final Map<String, http.Response Function()> routes;
  final List<String> calls = [];

  ClassLinkApi get api => ClassLinkApi(
    baseUrl: 'https://api.test',
    tokenProvider: () async => 'tok',
    client: MockClient((request) async {
      final key = '${request.method} ${request.url.path}';
      calls.add(key);
      final handler = routes[key];
      return handler == null ? _error('not_routed', 500) : handler();
    }),
  );
}

Map<String, http.Response Function()> _liveRoutes(
  String sessionId, {
  List<Map<String, Object?>> roster = const [],
}) => {
  'POST /v1/sessions': () => _json(_session(sessionId), 201),
  'GET /v1/sessions/$sessionId/token': () => _json(_token),
  'GET /v1/sessions/$sessionId/roster': () => _json(roster),
};

void main() {
  late MemoryStore store;
  late FakeBroadcaster radio;

  setUp(() {
    store = MemoryStore();
    radio = FakeBroadcaster();
  });

  TeacherSessionController controllerFor(FakeServer server) {
    final c = TeacherSessionController(
      api: server.api,
      store: store,
      classroom: _classroom,
      broadcaster: radio,
    );
    addTearDown(c.dispose);
    return c;
  }

  test('begin starts a session, saves its id and goes live', () async {
    final server = FakeServer(_liveRoutes('s-1'));
    final c = controllerFor(server);
    await c.begin();
    expect(c.phase, SessionPhase.live);
    expect(c.session?.id, 's-1');
    expect(store.values[_activeKey], 's-1');
    expect(radio.state, BroadcastState.broadcasting);
    expect(radio.lastToken, hasLength(17));
    expect(c.roomCode, isNotNull);
  });

  test('roster lists present students first, then by roll number or name',
      () async {
    final server = FakeServer(
      _liveRoutes(
        's-1',
        roster: [
          _row('Zed', '1024160130', null),
          _row('Mahi', '1024160102', 'present'),
          _row('Anon', null, null),
          _row('Ada', '1024160120', 'absent'),
          _row('Khagendra', '1024160123', 'present'),
        ],
      ),
    );
    final c = controllerFor(server);
    await c.begin();
    expect(c.roster.map((r) => r.fullName).toList(), [
      'Mahi',
      'Khagendra',
      'Ada',
      'Zed',
      'Anon',
    ]);
    expect(c.presentCount, 2);
  });

  test('a session running on another phone is resumed from the server',
      () async {
    final server = FakeServer({
      ..._liveRoutes('s-other'),
      'POST /v1/sessions': () => _error('active_session_exists', 409),
      'GET /v1/classrooms/room-1/sessions/active': () =>
          _json(_session('s-other')),
    });
    final c = controllerFor(server);
    await c.begin();
    expect(c.phase, SessionPhase.live);
    expect(c.session?.id, 's-other');
    expect(store.values[_activeKey], 's-other');
    expect(server.calls, contains('GET /v1/sessions/s-other/token'));
  });

  test('a stale saved id is replaced by the session the server reports',
      () async {
    store.values[_activeKey] = 's-stale';
    final server = FakeServer({
      ..._liveRoutes('s-live'),
      'POST /v1/sessions': () => _error('active_session_exists', 409),
      'GET /v1/classrooms/room-1/sessions/active': () =>
          _json(_session('s-live')),
    });
    final c = controllerFor(server);
    await c.begin();
    expect(c.session?.id, 's-live');
    expect(store.values[_activeKey], 's-live');
  });

  test('resume fails with a clear message if the session ended meanwhile',
      () async {
    final server = FakeServer({
      'POST /v1/sessions': () => _error('active_session_exists', 409),
      'GET /v1/classrooms/room-1/sessions/active': () =>
          _error('no_active_session', 404),
    });
    final c = controllerFor(server);
    await c.begin();
    expect(c.phase, SessionPhase.failed);
    expect(c.error, 'This classroom has no session running.');
  });

  test('begin fails when Bluetooth does not start', () async {
    radio = FakeBroadcaster(fails: true);
    final c = controllerFor(FakeServer(_liveRoutes('s-1')));
    await c.begin();
    expect(c.phase, SessionPhase.failed);
    expect(c.error, 'Bluetooth is off.');
  });

  test('end stops the radio, forgets the session and keeps the roster',
      () async {
    final server = FakeServer({
      ..._liveRoutes('s-1', roster: [_row('Mahi', '1024160102', 'present')]),
      'POST /v1/sessions/s-1/end': () =>
          _json(_session('s-1', endedAt: '2026-11-26T10:00:00Z')),
    });
    final c = controllerFor(server);
    await c.begin();
    await c.end();
    expect(c.phase, SessionPhase.ended);
    expect(c.session?.isActive, isFalse);
    expect(radio.stops, greaterThan(0));
    expect(radio.state, BroadcastState.idle);
    expect(store.values.containsKey(_activeKey), isFalse);
    expect(c.roster.single.fullName, 'Mahi');
  });

  test('end treats an already ended session as ended', () async {
    final server = FakeServer({
      ..._liveRoutes('s-1'),
      'POST /v1/sessions/s-1/end': () => _error('session_already_ended', 409),
    });
    final c = controllerFor(server);
    await c.begin();
    await c.end();
    expect(c.phase, SessionPhase.ended);
    expect(store.values.containsKey(_activeKey), isFalse);
  });

  test('a failed end keeps the session live and shows a warning', () async {
    final server = FakeServer({
      ..._liveRoutes('s-1'),
      'POST /v1/sessions/s-1/end': () => _error('network_error', 503),
    });
    final c = controllerFor(server);
    await c.begin();
    await c.end();
    expect(c.phase, SessionPhase.live);
    expect(c.warning, startsWith('Could not end the session'));
    expect(store.values[_activeKey], 's-1');
    expect(radio.state, BroadcastState.broadcasting);
  });
}
