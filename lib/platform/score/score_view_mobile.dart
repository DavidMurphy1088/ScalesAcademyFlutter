import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../score/score_spec.dart';
import 'score_view.dart';

/// Android and iOS: the score page (assets/score/score.html) runs in a web view.
/// Dart -> page: runJavaScript. Page -> Dart: the JavaScript channel "SAF".
class MobileScoreController implements ScoreController {
  final _messages = StreamController<ScoreMessage>.broadcast();
  final _ready = Completer<void>();
  late final WebViewController _web;

  MobileScoreController() {
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      // Added before the page loads, so window.SAF exists when score.html starts
      ..addJavaScriptChannel('SAF', onMessageReceived: (message) => _onMessage(message.message))
      ..loadFlutterAsset('assets/score/score.html');
  }

  void _onMessage(String text) {
    try {
      final message = ScoreMessage.fromJson(jsonDecode(text) as Map<String, dynamic>);
      if (message.type == 'ready' && !_ready.isCompleted) _ready.complete();
      _messages.add(message);
    } catch (e) {
      debugPrint('Score: bad message "$text": $e');
    }
  }

  void _run(String script) {
    _web.runJavaScript(script).catchError((Object e) {
      debugPrint('Score: JavaScript failed: $e');
    });
  }

  @override
  Stream<ScoreMessage> get messages => _messages.stream;

  @override
  bool get isReady => _ready.isCompleted;

  @override
  Future<void> load(ScoreSpec spec) async {
    await _ready.future;
    // jsonEncode twice: the spec as a JSON string, written as a JavaScript string literal
    _run('SAFScore.load(${jsonEncode(jsonEncode(spec.toJson()))})');
  }

  @override
  void highlight(Hand hand, int index, bool on, {int? seq}) {
    if (!isReady) return;
    _run('SAFScore.highlight("${hand.name}", $index, $on, ${seq ?? 'null'})');
  }

  @override
  void clear() {
    if (isReady) _run('SAFScore.clear()');
  }

  @override
  Widget buildView() => WebViewWidget(controller: _web);

  @override
  void dispose() {
    _messages.close();
  }
}

ScoreController createScoreController() => MobileScoreController();
