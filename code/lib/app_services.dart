import 'dart:io';

import 'package:flutter/widgets.dart';

import 'api/api_client.dart';
import 'auth/auth_service.dart';
import 'config.dart';
import 'crypto/device_key.dart';
import 'util/secure_store.dart';

/// Everything the screens share, built once at start up.
class AppServices {
  final AppConfig config;
  final SecureStore store;
  final AuthService auth;
  final ClassLinkApi api;
  final DeviceKeyStore keys;

  AppServices({
    required this.config,
    required this.store,
    required this.auth,
    required this.api,
    required this.keys,
  });

  factory AppServices.create({AppConfig? config, SecureStore? store}) {
    final cfg = config ?? AppConfig.fromEnvironment();
    final st = store ?? PlatformSecureStore();
    final auth = AuthService(cfg, st);
    return AppServices(
      config: cfg,
      store: st,
      auth: auth,
      api: ClassLinkApi(
        baseUrl: cfg.apiBaseUrl,
        tokenProvider: auth.validAccessToken,
      ),
      keys: DeviceKeyStore(st),
    );
  }

  /// Students: make sure the server holds this phone's public key. Binding
  /// a new key revokes the old one, so a student has one phone at a time.
  Future<void> ensureDeviceBound(String userId) async {
    final key = await keys.loadOrCreate();
    if (await keys.isBoundFor(userId, key)) return;
    await api.bindDevice(
      publicKeyBase64: key.publicKeyBase64,
      label: '${Platform.operatingSystem} phone',
    );
    await keys.markBoundFor(userId, key);
  }

  Future<void> signOut() async {
    final userId = auth.session?.userId;
    if (userId != null) await keys.forgetBindingFor(userId);
    await auth.signOut();
  }
}

class AppScope extends InheritedWidget {
  final AppServices services;

  const AppScope({super.key, required this.services, required super.child});

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      services != oldWidget.services;
}
