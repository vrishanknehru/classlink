/// Build time settings, passed with `--dart-define`.
///
///     flutter run \
///       --dart-define=API_BASE_URL=https://classlink-api.onrender.com \
///       --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///       --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// Leave the Supabase values out to get the developer sign in screen, which
/// takes a token from `backend/scripts/dev_token.py` for the local stack.
class AppConfig {
  final String apiBaseUrl;
  final String supabaseUrl;
  final String supabaseAnonKey;

  const AppConfig({
    required this.apiBaseUrl,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  /// Where the Android emulator sees the docker compose API on the host.
  static const localApi = 'http://10.0.2.2:8000';

  factory AppConfig.fromEnvironment() => AppConfig(
    // An empty define (CI with the variable unset) falls back too.
    apiBaseUrl: _trimSlash(
      const String.fromEnvironment('API_BASE_URL').isEmpty
          ? localApi
          : const String.fromEnvironment('API_BASE_URL'),
    ),
    supabaseUrl: _trimSlash(const String.fromEnvironment('SUPABASE_URL')),
    supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
