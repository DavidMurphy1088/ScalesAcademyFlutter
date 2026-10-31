import 'package:flutter/widgets.dart';

import '../../score/score_spec.dart';
// Android/iOS: OSMD in a web view. Web: OSMD drawn straight into the page. Only one is compiled into each app.
import 'score_view_mobile.dart' if (dart.library.js_interop) 'score_view_web.dart' as impl;

/// A message from the score page (assets/score/score.js)
class ScoreMessage {
  /// 'ready', 'rendered', 'error' or 'highlighted'
  final String type;

  /// 'rendered': how long building and drawing the score took in JavaScript
  final int? ms;

  /// 'rendered': how many notes were drawn for each hand
  final int rightNotes;
  final int leftNotes;

  /// 'error': what went wrong
  final String? message;

  /// 'highlighted': the sequence number of the highlight being acknowledged
  final int? seq;

  /// 'rendered': drawn again because the score's space changed size (not because Dart asked for it)
  final bool redraw;

  const ScoreMessage(
      {required this.type, this.ms, this.rightNotes = 0, this.leftNotes = 0, this.message, this.seq, this.redraw = false});

  factory ScoreMessage.fromJson(Map<String, dynamic> json) {
    final notes = json['notes'] as Map<String, dynamic>?;
    return ScoreMessage(
      type: json['type'] as String,
      ms: (json['ms'] as num?)?.round(),
      rightNotes: (notes?['right'] as num?)?.toInt() ?? 0,
      leftNotes: (notes?['left'] as num?)?.toInt() ?? 0,
      message: json['message'] as String?,
      seq: (json['seq'] as num?)?.toInt(),
      redraw: json['redraw'] == true,
    );
  }
}

/// Draws scores with OpenSheetMusicDisplay and highlights notes (SA's green ring) - the same API on every platform.
/// The score page itself (assets/score/score.html, score.js, osmd.min.js) is shared by all platforms.
abstract class ScoreController {
  /// The controller for the platform the app is running on
  factory ScoreController() => impl.createScoreController();

  /// Messages from the score page: ready, rendered, error, highlighted
  Stream<ScoreMessage> get messages;

  /// True once the score page has loaded OSMD
  bool get isReady;

  /// Draws [spec]. It is drawn again automatically when the score's space changes size.
  Future<void> load(ScoreSpec spec);

  /// Shows or hides the ring round note [index] (in playing order) of [hand]'s stave.
  /// With [seq], the page replies with a 'highlighted' message carrying it (to time the round trip).
  void highlight(Hand hand, int index, bool on, {int? seq});

  /// Hides all rings
  void clear();

  /// The widget showing the score
  Widget buildView();

  void dispose();
}

/// Shows the score drawn by [controller]
class ScoreView extends StatelessWidget {
  final ScoreController controller;

  const ScoreView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => controller.buildView();
}
