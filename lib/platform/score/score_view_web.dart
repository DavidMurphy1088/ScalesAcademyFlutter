import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../score/score_spec.dart';
import 'score_view.dart';

// window.SAFScore, defined by assets/score/score.js
@JS('SAFScore')
external _SAFScore? get _safScore;

extension type _SAFScore._(JSObject _) implements JSObject {
  external void init(web.HTMLElement element, JSFunction send);
  external JSPromise<JSAny?> load(String specJson);
  external void highlight(String hand, int index, bool on, int? seq);
  external void clear();
}

/// The web: osmd.min.js and score.js are loaded into the app's own page (once), and OSMD draws into a
/// <div> shown with an HtmlElementView. No web view or iframe.
class WebScoreController implements ScoreController {
  static int _nextId = 0;
  static Future<void>? _scriptsLoaded;

  final _messages = StreamController<ScoreMessage>.broadcast();
  final _ready = Completer<void>();
  final String _viewType = 'saf-score-${_nextId++}';
  final web.HTMLDivElement _div = web.HTMLDivElement();

  WebScoreController() {
    _div.style
      ..width = '100%'
      ..height = '100%'
      ..backgroundColor = '#FFFFFF';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _div);
    _start();
  }

  Future<void> _start() async {
    try {
      await (_scriptsLoaded ??= _loadScripts());
      final score = _safScore;
      if (score == null) throw StateError('score.js did not load');
      score.init(_div, ((JSString message) => _onMessage(message.toDart)).toJS);
    } catch (e) {
      _messages.add(ScoreMessage(type: 'error', message: 'Score page did not start: $e'));
    }
  }

  /// Adds osmd.min.js, then score.js, to the page.
  /// osmd.min.js is a UMD bundle: if the page has an AMD loader (window.define - Flutter's debug web builds
  /// may), it would register itself as an AMD module instead of the global "opensheetmusicdisplay" that
  /// score.js uses. So define is hidden while it loads.
  static Future<void> _loadScripts() async {
    final savedDefine = globalContext['define'];
    globalContext['define'] = null;
    try {
      for (final asset in ['assets/score/osmd.min.js', 'assets/score/score.js']) {
        final loaded = Completer<void>();
        final script = web.HTMLScriptElement()..src = ui_web.assetManager.getAssetUrl(asset);
        script.addEventListener('load', ((web.Event _) => loaded.complete()).toJS);
        script.addEventListener('error', ((web.Event _) => loaded.completeError('could not load $asset')).toJS);
        web.document.head!.appendChild(script);
        await loaded.future;
      }
    } finally {
      globalContext['define'] = savedDefine;
    }
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

  @override
  Stream<ScoreMessage> get messages => _messages.stream;

  @override
  bool get isReady => _ready.isCompleted;

  @override
  Future<void> load(ScoreSpec spec) async {
    await _ready.future;
    _safScore?.load(jsonEncode(spec.toJson()));
  }

  @override
  void highlight(Hand hand, int index, bool on, {int? seq}) {
    if (!isReady) return;
    _safScore?.highlight(hand.name, index, on, seq);
  }

  @override
  void clear() {
    if (isReady) _safScore?.clear();
  }

  @override
  Widget buildView() => HtmlElementView(viewType: _viewType);

  @override
  void dispose() {
    _messages.close();
  }
}

ScoreController createScoreController() => WebScoreController();
