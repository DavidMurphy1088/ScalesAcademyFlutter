import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'log/test_log.dart';
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
  // The test log starts with the app (title bar buttons: Log to console, Copy log, Clear)
  TestLog.instance.start();
  _logUnexpectedErrors();
  runApp(const ScalesAcademyFlutterApp());
}

/// Unexpected errors (bugs) also go into the test log as ERROR lines, with the start of the stack trace, as well as
/// to the console as before:
/// - errors Flutter catches while building, laying out or drawing the screen (FlutterError.onError)
/// - any other uncaught error, e.g. in a timer or an async call (PlatformDispatcher.onError)
void _logUnexpectedErrors() {
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    previousFlutterHandler?.call(details); // the console report, as before
    _logError('${details.exceptionAsString()}'
        '${details.context == null ? '' : ' (${details.context!.toDescription()})'}', details.stack);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _logError('$error', stack);
    return false; // not handled here: Flutter still reports it to the console as before
  };
}

bool _loggingError = false;

void _logError(String message, StackTrace? stack) {
  final frames = stack == null
      ? <String>[]
      : stack.toString().split('\n').where((l) => l.trim().isNotEmpty).take(6).map((l) => '    $l').toList();
  // Added after the current frame: an error while the screen is being built must not change the screen during the
  // build (the title bar shows the log's line count)
  scheduleMicrotask(() {
    if (_loggingError) return; // never let a failure here cause another error report
    _loggingError = true;
    try {
      TestLog.instance.add(['ERROR'], [message, ...frames].join('\n'));
    } finally {
      _loggingError = false;
    }
  });
}

/// SA Flutter: Scales Academy for iOS, Android and the web, in Flutter.
/// Test screens so far: Listen (Stage 0, from FlutterTest), Sound (Stage 1) and Score (Stages 2-3).
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
