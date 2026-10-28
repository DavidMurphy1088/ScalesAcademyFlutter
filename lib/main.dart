import 'package:flutter/material.dart';

import 'screens/listen_page.dart';

void main() {
  runApp(const ScalesAcademyFlutterApp());
}

/// SA Flutter: Scales Academy for iOS, Android and the web, in Flutter.
/// Stage 0: the project skeleton, with the microphone listening screen carried over from FlutterTest (FL).
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
      home: const ListenPage(),
    );
  }
}
