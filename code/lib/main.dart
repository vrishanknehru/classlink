import 'package:flutter/material.dart';

import 'screens/role_select_screen.dart';

void main() {
  runApp(const ClassLinkApp());
}

class ClassLinkApp extends StatelessWidget {
  const ClassLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClassLink BLE POC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const RoleSelectScreen(),
    );
  }
}
