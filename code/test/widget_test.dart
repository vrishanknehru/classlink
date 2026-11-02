import 'package:classlink/app_services.dart';
import 'package:classlink/config.dart';
import 'package:classlink/main.dart';
import 'package:classlink/util/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('signed out users see sign in', (tester) async {
    final services = AppServices.create(
      config: const AppConfig(
        apiBaseUrl: 'https://api.test',
        supabaseUrl: 'https://sb.test',
        supabaseAnonKey: 'anon',
      ),
      store: MemoryStore(),
    );
    await tester.pumpWidget(ClassLinkApp(services: services));
    expect(find.text('ClassLink'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Server: https://api.test'), findsOneWidget);
  });

  testWidgets('builds without Supabase show the developer sign in', (
    tester,
  ) async {
    final services = AppServices.create(
      config: const AppConfig(
        apiBaseUrl: 'http://10.0.2.2:8000',
        supabaseUrl: '',
        supabaseAnonKey: '',
      ),
      store: MemoryStore(),
    );
    await tester.pumpWidget(ClassLinkApp(services: services));
    expect(find.text('Use token'), findsOneWidget);
  });
}
