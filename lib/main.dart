import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape only, as SA (also set in ios/Runner/Info.plist and android/app/src/main/AndroidManifest.xml)
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  // OpenSheetMusicDisplay's BSD licence, shown in the app's licence page
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
        ['opensheetmusicdisplay'], await rootBundle.loadString('assets/score/OSMD_LICENSE.txt'));
  });
  runApp(const ScalesAcademyFlutterApp());
}

/// SA Flutter: Scales Academy for iOS, Android and the web, in Flutter.
/// Test screens so far: Listen (Stage 0, from FlutterTest), Sound (Stage 1) and Score (Stage 2).
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
