import 'package:flutter/material.dart';

import 'screens/home_page.dart';

void main() {
  runApp(const ScalesAcademyFlutterApp());
}

/// SA Flutter: Scales Academy for iOS, Android and the web, in Flutter.
/// Test screens so far: Listen (Stage 0, from FlutterTest) and Sound (Stage 1).
class ScalesAcademyFlutterApp extends StatelessWidget {
  const ScalesAcademyFlutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SA Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomePage(),
    );
  }
}
