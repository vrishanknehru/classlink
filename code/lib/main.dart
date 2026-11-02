import 'package:flutter/material.dart';

import 'app_services.dart';
import 'screens/home_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = AppServices.create();
  await services.auth.restore();
  runApp(ClassLinkApp(services: services));
}

class ClassLinkApp extends StatelessWidget {
  final AppServices services;

  const ClassLinkApp({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3949AB));
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'ClassLink',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: scheme,
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3949AB),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: const HomeGate(),
      ),
    );
  }
}
