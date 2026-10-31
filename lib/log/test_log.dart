import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The app's test log (31 Oct 2026): starts when the app starts and records every test on every test screen,
/// one line each, prefixed with the time and the test's settings (screen, exercise, tempo, ...).
/// - Log to console: the whole log to the console (the Terminal running `flutter run` / `./run.sh`, or the browser's
///   console), between START and END lines, to copy into a message
/// - Copy log: the whole log to the clipboard, e.g. to paste into an email
/// - Clear: empties the log (a new header line starts it again)
/// Kept in memory only: it is lost when the app closes.
class TestLog extends ChangeNotifier {
  TestLog._();

  static final TestLog instance = TestLog._();

  final List<String> _lines = [];
  Size? _screenSize;

  List<String> get lines => List.unmodifiable(_lines);
  int get length => _lines.length;

  /// e.g. "iOS release", "Android debug", "Web release"
  static String get platformName {
    final mode = kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');
    if (kIsWeb) return 'Web $mode';
    final os = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.macOS => 'macOS',
      _ => defaultTargetPlatform.name,
    };
    return '$os $mode';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  static String _date(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';

  /// Called once at app start (main.dart), and again after Clear when the next line is added
  void start() {
    if (_lines.isNotEmpty) return;
    final now = DateTime.now();
    final size = _screenSize;
    _lines.add('SAF test log, $platformName, ${_date(now)} ${_time(now)}'
        '${size == null ? '' : ', screen ${size.width.round()}x${size.height.round()}'}');
  }

  /// The screen size for the header line (set by the app's first screen). A zero size is ignored: on Android the
  /// first screen can be built before the window has its size.
  void setScreenSize(Size size) {
    if (size.isEmpty) return;
    if (_screenSize == null) {
      _screenSize = size;
      if (_lines.length == 1 && !_lines.first.contains(', screen ')) {
        _lines[0] = '${_lines.first}, screen ${size.width.round()}x${size.height.round()}';
      }
    }
  }

  /// Adds one test result. [settings]: the test-wide settings, e.g. ['Score', 'F Melodic Minor, Right Hand', '♩=120'].
  /// A [message] with several lines is added line by line, each with the same prefix.
  void add(List<String> settings, String message) {
    start();
    final prefix = '[${_time(DateTime.now())}] [${settings.where((s) => s.isNotEmpty).join(' | ')}]';
    for (final line in message.trimRight().split('\n')) {
      _lines.add('$prefix $line');
    }
    notifyListeners();
  }

  String get text => _lines.join('\n');

  /// Log to console: every line, between START and END lines. One print per line, so long logs aren't cut short
  /// (Android cuts single console lines at about 4000 characters).
  void printToConsole() {
    start();
    // Two blank lines first, so each press's block stands apart in the console
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('===== SAF TEST LOG START (${_lines.length} lines) =====');
    for (final line in _lines) {
      // ignore: avoid_print
      print(line);
    }
    // ignore: avoid_print
    print('===== SAF TEST LOG END =====');
  }

  /// Copy log: the whole log to the clipboard (e.g. to paste into an email)
  Future<void> copyToClipboard() async {
    start();
    await Clipboard.setData(ClipboardData(text: text));
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
