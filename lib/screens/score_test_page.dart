import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../log/test_log.dart';
import '../music/abrsm_grade5.dart';
import '../music/scale.dart';
import '../platform/platform_services.dart';
import '../platform/score/score_view.dart';
import '../platform/sound/sound_player.dart';
import '../playback/scale_player.dart';
import '../score/scale_score.dart';
import '../score/score_spec.dart';
import 'common.dart';

/// Score test screen (Stages 2-3): SA's ABRSM Grade 5 exercises from SAF's port of SA's scale model, drawn by OSMD as
/// SA lays them out, with SA's choice of hands for hands-together exercises, played at their tempo with SA's green ring
/// following the notes. Shows how long drawing took and how quickly the page answers each highlight.
class ScoreTestPage extends StatefulWidget {
  const ScoreTestPage({super.key});

  @override
  State<ScoreTestPage> createState() => _ScoreTestPageState();
}

class _ScoreTestPageState extends State<ScoreTestPage> {
  final SoundPlayer _sound = PlatformServices.instance.sound;
  final ScoreController _score = ScoreController();
  late final ScalePlayer _player = ScalePlayer(_sound)
    ..onNote = _onNote
    ..onFinished = _onFinished;
  StreamSubscription<ScoreMessage>? _subscription;

  /// SA's Grade 5 list, and the exercise chosen from it
  final List<Scale> _exercises = abrsmGrade5();
  Scale? _exercise;

  /// The hands shown and played: the exercise's own, or one hand of a hands-together exercise (SA Select Hands)
  List<int> _hands = const [0, 1];

  /// The exercise with the chosen hands, and its score
  Scale? _shown;
  ScoreSpec? _scale;
  int _tempo = 120;
  bool _metronome = true;
  bool _playing = false;
  bool _startingSound = false;
  int? _ringIndex;

  String _scoreStatus = 'Starting the score page…';
  String? _playStatus;
  final _loadTimer = Stopwatch();

  // Highlight round trips: Dart sends the highlight, the page answers once the ring is shown
  int _seq = 0;
  final Map<int, Stopwatch> _sent = {};
  int _replies = 0;
  double _totalReplyMs = 0;
  double _worstReplyMs = 0;

  /// The test-wide settings that start each test log line from this screen
  List<String> get _logSettings => [
        'Score',
        _shown?.title ?? '',
        '♩=$_tempo',
        'metronome ${_metronome ? 'on' : 'off'}',
        _sound.piano.label,
      ];

  void _addToReport(String line) => TestLog.instance.add(_logSettings, line);

  @override
  void initState() {
    super.initState();
    _subscription = _score.messages.listen(_onScoreMessage);
    _loadScales();
  }

  @override
  void dispose() {
    _player.stop();
    _subscription?.cancel();
    _score.dispose();
    super.dispose();
  }

  void _loadScales() {
    _chooseExercise(_exercises.first);
  }

  void _chooseExercise(Scale exercise) {
    _exercise = exercise;
    _chooseHands(exercise.hands);
  }

  /// [hands]: [0, 1] together, [0] right, [1] left
  void _chooseHands(List<int> hands) {
    final exercise = _exercise!;
    final shown = _sameHands(hands, exercise.hands) ? exercise : exercise.withHands(hands);
    final ScoreSpec scale;
    try {
      scale = scoreSpecForScale(shown);
    } catch (e) {
      setState(() => _scoreStatus = 'Could not make the score: $e');
      _addToReport('Error making the score: $e');
      return;
    }
    _stop();
    setState(() {
      _hands = hands;
      _shown = shown;
      _scale = scale;
      _tempo = scale.tempo;
      _ringIndex = null;
      _scoreStatus = _score.isReady ? 'Drawing…' : 'Starting the score page…';
    });
    _loadTimer
      ..reset()
      ..start();
    // After the next frame: the score's box takes its new height first (one or two staves), so the score is drawn
    // once at the right size - not at the old size and then again
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_scale, scale)) _score.load(scale);
    });
  }

  static bool _sameHands(List<int> a, List<int> b) => a.length == b.length && a.every(b.contains);

  void _onScoreMessage(ScoreMessage message) {
    if (!mounted) return;
    switch (message.type) {
      case 'ready':
        setState(() => _scoreStatus = 'Drawing…');
      case 'rendered':
        final counts = [
          if (message.rightNotes > 0) 'RH ${message.rightNotes}',
          if (message.leftNotes > 0) 'LH ${message.leftNotes}',
        ].join(', ');
        if (message.redraw) {
          _addToReport('Redraw (score area changed size): ${message.ms} ms (OSMD). Notes: $counts');
        } else {
          _loadTimer.stop();
          setState(() => _scoreStatus = 'Drawn in ${message.ms} ms (OSMD); '
              '${_loadTimer.elapsedMilliseconds} ms from choosing it. Notes: $counts');
          _addToReport('Draw: $_scoreStatus');
        }
      case 'error':
        setState(() => _scoreStatus = 'Score error: ${message.message}');
        _addToReport('Score error: ${message.message}');
      case 'highlighted':
        final timer = _sent.remove(message.seq);
        if (timer != null) {
          final ms = timer.elapsedMicroseconds / 1000.0;
          _replies++;
          _totalReplyMs += ms;
          _worstReplyMs = math.max(_worstReplyMs, ms);
        }
    }
  }

  /// Plays the scale (the right hand when both hands are shown; both rings follow)
  Future<void> _play() async {
    final scale = _scale;
    if (scale == null) return;
    if (!_sound.isReady) {
      // Browsers only allow sound after a tap: start it here, from the Play tap
      setState(() => _startingSound = true);
      try {
        await _sound.init();
      } catch (e) {
        if (mounted) setState(() => _playStatus = 'Sound could not start: $e');
        _addToReport('Error: sound could not start: $e');
        return;
      } finally {
        if (mounted) setState(() => _startingSound = false);
      }
      if (!mounted) return;
    }
    final shown = _shown!;
    // The right hand's notes when it is shown, otherwise the left hand's
    final playHand = shown.hands.contains(0) ? 0 : 1;
    final notes = [for (final n in shown.notesOf(playHand)) n.midi];
    _score.clear();
    _seq = 0;
    _sent.clear();
    _replies = 0;
    _totalReplyMs = 0;
    _worstReplyMs = 0;
    _player.play(ScalePlan(notes: notes, tempo: _tempo, metronome: _metronome));
    setState(() {
      _playing = true;
      _ringIndex = null;
      _playStatus = null;
    });
  }

  void _stop() {
    if (!_playing) return;
    _player.stop();
    _ringOff();
    setState(() {
      _playing = false;
      _playStatus = _timingText();
    });
    _addPlayToReport(stopped: true);
  }

  void _addPlayToReport({required bool stopped}) {
    final timing = _playStatus ?? '';
    _addToReport('Play${stopped ? ' (stopped early)' : ''}: ${timing.isEmpty ? 'no timing yet' : timing}');
  }

  /// As SA: the ring shows while the note sounds (legato: until the next note starts)
  void _onNote(int index, int midi) {
    _ringOff();
    _ringIndex = index;
    for (final stave in _scale!.staves) {
      final seq = _seq++;
      _sent[seq] = Stopwatch()..start();
      _score.highlight(stave.hand, index, true, seq: seq);
    }
  }

  void _ringOff() {
    final index = _ringIndex;
    if (index == null || _scale == null) return;
    for (final stave in _scale!.staves) {
      _score.highlight(stave.hand, index, false);
    }
    _ringIndex = null;
  }

  void _onFinished() {
    _ringOff();
    if (!mounted) return;
    setState(() {
      _playing = false;
      _playStatus = _timingText();
    });
    _addPlayToReport(stopped: false);
  }

  String _timingText() {
    final clock = _player.clock;
    final ticks = clock.ticksMeasured == 0
        ? ''
        : 'Timing over ${clock.ticksMeasured} ticks: average ${clock.averageLateMs.toStringAsFixed(1)} ms late, '
            'worst ${clock.worstLateMs.toStringAsFixed(1)} ms. ';
    final rings = _replies == 0
        ? ''
        : 'Highlight round trip over $_replies notes: average ${(_totalReplyMs / _replies).toStringAsFixed(1)} ms, '
            'worst ${_worstReplyMs.toStringAsFixed(1)} ms.';
    return '$ticks$rings';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = _scale;
    final exercise = _exercise;
    final staves = scale?.staves.length ?? 1;
    // About SA's share of a landscape phone screen per stave, larger on tablets
    final staveHeight = math.min(110.0, math.max(60.0, MediaQuery.sizeOf(context).height * 0.17));
    return Scaffold(
      appBar: saAppBar(context, 'SA Flutter – Score'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<Scale>(
                    isExpanded: true,
                    value: exercise,
                    items: [
                      for (final s in _exercises)
                        DropdownMenuItem(value: s, child: Text(s.title, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (s) {
                      if (s != null) _chooseExercise(s);
                    },
                  ),
                ),
                if (exercise != null && exercise.isHandsTogether) ...[
                  const SizedBox(width: 12),
                  // SA Select Hands: Hands Together, Practise Left Hand, Practise Right Hand
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'both', label: Text('Together')),
                      ButtonSegment(value: 'left', label: Text('LH')),
                      ButtonSegment(value: 'right', label: Text('RH')),
                    ],
                    selected: {_hands.length > 1 ? 'both' : (_hands.first == 1 ? 'left' : 'right')},
                    onSelectionChanged: (s) => _chooseHands(switch (s.first) {
                      'left' => const [1],
                      'right' => const [0],
                      _ => const [0, 1],
                    }),
                  ),
                ],
                const SizedBox(width: 12),
                Text('♩ = $_tempo'),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _metronome,
                      onChanged: _playing ? null : (v) => setState(() => _metronome = v ?? true),
                    ),
                    const Text('Metronome'),
                  ],
                ),
                const SizedBox(width: 12),
                _playing
                    ? FilledButton.icon(onPressed: _stop, icon: const Icon(Icons.stop), label: const Text('Stop'))
                    : FilledButton.icon(
                        onPressed: scale == null || _startingSound ? null : _play,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(_startingSound ? 'Starting sound…' : 'Play'),
                      ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: staveHeight * staves,
              decoration: BoxDecoration(border: Border.all(color: theme.dividerColor)),
              child: ScoreView(controller: _score),
            ),
          ],
        ),
      ),
    );
  }
}
