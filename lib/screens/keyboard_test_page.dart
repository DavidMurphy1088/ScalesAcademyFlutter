import 'dart:async';

import 'package:flutter/material.dart';

import '../input/note_input.dart';
import '../keyboard/exercise_keyboards.dart';
import '../keyboard/keyboard_model.dart';
import '../keyboard/piano_keyboard.dart';
import '../log/test_log.dart';
import '../music/abrsm_grade5.dart';
import '../music/midi.dart';
import '../music/scale.dart';
import '../platform/midi/midi_input.dart';
import '../platform/platform_services.dart';
import '../platform/sound/sound_player.dart';
import '../playback/scale_player.dart';
import 'common.dart';

/// Keyboard test screen (Stage 4): SA's keyboard for SA's ABRSM Grade 5 exercises, with SA's fingering for each
/// direction, and the three ways to play notes - the microphone, a MIDI keyboard (Bluetooth; Web MIDI in Chrome),
/// and the keys on the screen - all lighting the keys as SA does.
class KeyboardTestPage extends StatefulWidget {
  const KeyboardTestPage({super.key});

  @override
  State<KeyboardTestPage> createState() => _KeyboardTestPageState();
}

/// One choice in "Listen with"
class _ListenChoice {
  final ListenWith kind;
  final MidiDeviceInfo? device;

  const _ListenChoice(this.kind, [this.device]);

  String get label => switch (kind) {
    ListenWith.nothing => 'Screen keys only',
    ListenWith.microphone => 'Microphone',
    ListenWith.midi => device.toString(),
  };

  @override
  bool operator ==(Object other) => other is _ListenChoice && other.kind == kind && other.device?.id == device?.id;

  @override
  int get hashCode => Object.hash(kind, device?.id);
}

class _KeyboardTestPageState extends State<KeyboardTestPage> {
  final PlatformServices _services = PlatformServices.instance;
  SoundPlayer get _sound => _services.sound;
  MidiInput get _midi => _services.midi;
  late final NoteInput _input = NoteInput(pitch: _services.pitch, midi: _services.midi);
  late final ScalePlayer _player = ScalePlayer(_sound)
    ..onNote = _onPlayerNote
    ..onFinished = _onPlayerFinished;
  StreamSubscription<PlayedNote>? _notesSub;
  StreamSubscription<void>? _devicesSub;

  final List<Scale> _exercises = abrsmGrade5();
  Scale? _exercise;
  List<int> _hands = const [0, 1];
  Scale? _shown;
  ExerciseKeyboards? _keyboards;

  bool _showFingers = true;

  /// The keys on the screen sound and count as played notes (decision: playable, with a setting to turn it off)
  bool _screenKeysPlay = true;
  bool _metronome = true;
  bool _playing = false;
  bool _busy = false;

  _ListenChoice _listen = const _ListenChoice(ListenWith.nothing);
  List<MidiDeviceInfo> _devices = const [];
  String? _midiProblem;
  String _status = '';

  /// The last notes played, newest last, for the line under the controls
  final List<PlayedNote> _recent = [];

  /// Notes waiting to be written to the test log (written after a pause in playing)
  final List<PlayedNote> _unlogged = [];
  Timer? _logTimer;

  /// Check (MIDI): waiting for a key press
  Timer? _checkTimer;
  bool _checkWaiting = false;
  final _checkClock = Stopwatch();

  // Playing the scale to the user
  int? _playIndex;

  List<String> get _logSettings => [
    'Keyboard',
    _shown?.title ?? '',
    'listen: ${_listen.label}',
    'screen keys ${_screenKeysPlay ? 'play' : 'off'}',
    _sound.piano.label,
  ];

  void _log(String line) => TestLog.instance.add(_logSettings, line);

  @override
  void initState() {
    super.initState();
    _midi.log = _log;
    _notesSub = _input.notes.listen(_onPlayedNote);
    _devicesSub = _midi.devicesChanged.listen((_) => _refreshDevices(quiet: true));
    _chooseExercise(_exercises.first);
    if (_midi.isSupported) _refreshDevices(quiet: true);
  }

  @override
  void dispose() {
    _player.stop();
    _flushLog();
    _logTimer?.cancel();
    _checkTimer?.cancel();
    _notesSub?.cancel();
    _devicesSub?.cancel();
    _midi.log = null;
    _input.stop();
    _sound.allNotesOff();
    _keyboards?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- Exercise

  void _chooseExercise(Scale exercise) {
    _exercise = exercise;
    _chooseHands(exercise.hands);
  }

  void _chooseHands(List<int> hands) {
    _stopPlaying();
    final exercise = _exercise!;
    final same = hands.length == exercise.hands.length && hands.every(exercise.hands.contains);
    final shown = same ? exercise : exercise.withHands(hands);
    final old = _keyboards;
    final keyboards = ExerciseKeyboards(shown);
    setState(() {
      _hands = hands;
      _shown = shown;
      _keyboards = keyboards;
    });
    // After the new keyboards are on screen (the old ones' widgets release their keys first)
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    _log('Keyboards: ${_describeKeyboards(keyboards)}');
  }

  static String _describeKeyboards(ExerciseKeyboards k) {
    String one(KeyboardModel m) {
      final name = switch (m.hand) {
        0 => 'RH',
        1 => 'LH',
        _ => 'Joined',
      };
      final last = m.firstKeyMidi + m.keys.length - 1;
      final fingers = [
        for (final key in m.keys)
          if (key.scaleNoteState != null) '${midiName(key.noteMidi)}:${key.fingerText.isEmpty ? '-' : key.fingerText}',
      ].join(' ');
      return '$name ${midiName(m.firstKeyMidi)}-${midiName(last)} (${m.keys.length} keys) fingers $fingers';
    }

    return k.shown.map(one).join(' / ');
  }

  void _selectSegment(int segment) {
    final k = _keyboards;
    if (k == null) return;
    k.selectSegment(segment);
    setState(() {});
    _log('Direction: segment $segment (${k.isUpwards ? 'up' : 'down'}). ${_describeKeyboards(k)}');
  }

  // ---------------------------------------------------------------- Played notes

  void _onScreenKeyDown(int midi) {
    if (!_screenKeysPlay) return;
    if (_sound.isReady) {
      _sound.noteOn(midi);
    } else {
      _startSound();
    }
    _input.addFromScreen(midi, on: true);
  }

  void _onScreenKeyUp(int midi) {
    if (!_screenKeysPlay) return;
    // Fades over half a second, so a short tap still rings (David, 2 Nov 2026)
    if (_sound.isReady) _sound.noteOff(midi, release: const Duration(milliseconds: 500));
    _input.addFromScreen(midi, on: false);
  }

  Future<void> _startSound() async {
    if (_busy) return;
    _busy = true;
    try {
      final took = await _sound.init();
      _log('Sound started in ${took.inMilliseconds} ms (the first key press starts it, and is silent)');
    } catch (e) {
      _log('Error: sound could not start: $e');
    } finally {
      _busy = false;
    }
  }

  void _onPlayedNote(PlayedNote note) {
    if (!mounted || !note.on) return;
    // Keys pressed on the screen light themselves
    if (note.source != NoteSource.screen) _keyboards?.showPlayedNote(note.midi);
    if (_checkWaiting && note.source == NoteSource.midi) _checkPassed();
    setState(() {
      _recent.add(note);
      if (_recent.length > 16) _recent.removeAt(0);
    });
    _unlogged.add(note);
    _logTimer?.cancel();
    _logTimer = Timer(const Duration(seconds: 2), _flushLog);
  }

  /// Writes the notes played since the last pause to the test log, one line per source
  void _flushLog() {
    if (_unlogged.isEmpty) return;
    final scale = _shown;
    for (final source in NoteSource.values) {
      final notes = _unlogged.where((n) => n.source == source).toList();
      if (notes.isEmpty) continue;
      var inScale = 0;
      if (scale != null) {
        final scaleMidis = {for (final h in scale.hands) ...scale.notesOf(h).map((n) => n.midi)};
        inScale = notes.where((n) => scaleMidis.contains(n.midi)).length;
      }
      final secs = (notes.last.time - notes.first.time).inMilliseconds / 1000;
      _log(
        'Played (${source.label}): ${notes.map((n) => midiName(n.midi)).join(' ')} - ${notes.length} notes '
        'in ${secs.toStringAsFixed(1)} s, $inScale in the scale',
      );
    }
    _unlogged.clear();
  }

  // ---------------------------------------------------------------- Listen with

  Future<void> _refreshDevices({bool quiet = false}) async {
    if (!_midi.isSupported) return;
    try {
      final devices = await _midi.devices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _midiProblem = null;
      });
      if (!quiet) {
        _log('MIDI keyboards: ${devices.isEmpty ? 'none' : devices.join(', ')}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _midiProblem = '$e');
      _log('Error listing MIDI keyboards: $e');
    }
  }

  Future<void> _findBluetooth() async {
    setState(() {
      _busy = true;
      _status = _midi.bluetoothFinding == BluetoothFinding.scan ? 'Looking for Bluetooth MIDI keyboards…' : '';
    });
    try {
      final result = await _midi.findBluetoothKeyboards();
      _log(result);
      await _refreshDevices();
      if (mounted) setState(() => _status = result);
    } catch (e) {
      _log('Error finding Bluetooth keyboards: $e');
      if (mounted) setState(() => _status = 'Bluetooth: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseListen(_ListenChoice choice) async {
    _cancelCheck();
    _flushLog();
    setState(() {
      _busy = true;
      _status = 'Starting…';
    });
    String result;
    try {
      switch (choice.kind) {
        case ListenWith.nothing:
          await _input.stop();
          result = 'Listening to the screen keys only';
        case ListenWith.microphone:
          result = await _input.listenWithMicrophone();
        case ListenWith.midi:
          result = await _input.listenWithMidi(choice.device!);
      }
    } catch (e) {
      result = 'Could not listen with ${choice.label}: $e';
      await _input.stop();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _listen = switch (_input.listenWith) {
        ListenWith.nothing => const _ListenChoice(ListenWith.nothing),
        ListenWith.microphone => const _ListenChoice(ListenWith.microphone),
        ListenWith.midi => _ListenChoice(ListenWith.midi, _midi.connected),
      };
      _status = result;
    });
    _log(result);
  }

  /// SA Settings > Check: wait up to 10 s for a key press from the MIDI keyboard
  void _startCheck() {
    _cancelCheck();
    _midi.counts.reset();
    _checkClock
      ..reset()
      ..start();
    setState(() {
      _checkWaiting = true;
      _status = 'Check: press a key on ${_listen.label}…';
    });
    _log('Check started: waiting 10 s for a key press from ${_listen.label}');
    _checkTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_checkWaiting) return;
      final line = 'Check: no notes received from ${_listen.label} in 10 s. What arrived: ${_midi.counts}';
      setState(() {
        _checkWaiting = false;
        _status = line;
      });
      _log(line);
    });
  }

  void _checkPassed() {
    _checkTimer?.cancel();
    final line =
        'Check: notes received from ${_listen.label} after '
        '${(_checkClock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s';
    setState(() {
      _checkWaiting = false;
      _status = line;
    });
    _log(line);
  }

  void _cancelCheck() {
    _checkTimer?.cancel();
    if (_checkWaiting) _log('Check cancelled');
    _checkWaiting = false;
  }

  // ---------------------------------------------------------------- Play the scale (keys light as it plays)

  /// As SA HearScalePlayer: the scale is played (the right hand when both are shown), each key ringed while its
  /// note sounds, and the fingering switches direction as the scale turns
  Future<void> _play() async {
    final shown = _shown;
    final keyboards = _keyboards;
    if (shown == null || keyboards == null) return;
    if (!_sound.isReady) {
      setState(() => _busy = true);
      try {
        await _sound.init();
      } catch (e) {
        _log('Error: sound could not start: $e');
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (!mounted) return;
    }
    final playHand = shown.hands.contains(0) ? 0 : 1;
    keyboards.hilightNotesOutsideScale = false;
    keyboards.clearSounding();
    _playIndex = null;
    _player.play(
      ScalePlan(
        notes: [for (final n in shown.notesOf(playHand)) n.midi],
        tempo: shown.minTempo,
        notesPerBeat: shown.scaleType.isBrokenChord ? 3 : 2,
        metronome: _metronome,
      ),
    );
    setState(() => _playing = true);
    _log('Play at ♩=${shown.minTempo}');
  }

  void _onPlayerNote(int index, int midi) {
    final shown = _shown;
    final keyboards = _keyboards;
    if (shown == null || keyboards == null || !mounted) return;
    _ringsOff();
    final playHand = shown.hands.contains(0) ? 0 : 1;
    final segment = shown.notesOf(playHand)[index].segments.first;
    if (segment != keyboards.segment) {
      keyboards.selectSegment(segment);
      setState(() {});
    }
    for (final hand in shown.hands) {
      final notes = shown.notesOf(hand);
      if (index >= notes.length) continue;
      final keyboard = keyboards.keyboardFor(hand);
      final key = keyboard.keyIndexForMidi(notes[index].midi);
      if (key != null) keyboard.setKeySounding(key, true);
    }
    _playIndex = index;
  }

  void _ringsOff() {
    final index = _playIndex;
    final shown = _shown;
    final keyboards = _keyboards;
    if (index == null || shown == null || keyboards == null) return;
    for (final hand in shown.hands) {
      final notes = shown.notesOf(hand);
      if (index >= notes.length) continue;
      final keyboard = keyboards.keyboardFor(hand);
      final key = keyboard.keyIndexForMidi(notes[index].midi);
      if (key != null) keyboard.setKeySounding(key, false);
    }
    _playIndex = null;
  }

  void _onPlayerFinished() {
    _ringsOff();
    _keyboards?.hilightNotesOutsideScale = true;
    if (!mounted) return;
    setState(() => _playing = false);
    _log('Played to the end. ${_timing()}');
  }

  void _stopPlaying() {
    if (!_playing) return;
    _player.stop();
    _ringsOff();
    _keyboards?.hilightNotesOutsideScale = true;
    setState(() => _playing = false);
    _log('Play stopped early. ${_timing()}');
  }

  String _timing() {
    final clock = _player.clock;
    if (clock.ticksMeasured == 0) return '';
    return 'Timing over ${clock.ticksMeasured} ticks: average ${clock.averageLateMs.toStringAsFixed(1)} ms late, '
        'worst ${clock.worstLateMs.toStringAsFixed(1)} ms.';
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    final keyboards = _keyboards;
    final shown = _shown;
    return Scaffold(
      appBar: saAppBar(context, 'SA Flutter – Keyboard'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _exerciseRow(exercise),
              _listenRow(),
              _statusLine(),
              const SizedBox(height: 4),
              if (keyboards != null && shown != null)
                for (final (i, model) in keyboards.shown.indexed) ...[
                  if (i > 0) const SizedBox(height: 6),
                  Expanded(
                    child: PianoKeyboard(
                      model: model,
                      scale: shown,
                      showFingers: _showFingers,
                      onKeyDown: _screenKeysPlay ? _onScreenKeyDown : null,
                      onKeyUp: _screenKeysPlay ? _onScreenKeyUp : null,
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _exerciseRow(Scale? exercise) {
    final keyboards = _keyboards;
    final (lo, hi) = keyboards?.minMaxSegments ?? (0, 0);
    final segment = keyboards?.segment ?? 0;
    final direction = keyboards == null ? '' : (keyboards.isUpwards ? 'Up' : 'Down');
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: DropdownButton<Scale>(
            isExpanded: true,
            isDense: true,
            value: exercise,
            items: [
              for (final s in _exercises)
                DropdownMenuItem(
                  value: s,
                  child: Text(s.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (s) {
              if (s != null) _chooseExercise(s);
            },
          ),
        ),
        _fitted([
          if (exercise != null && exercise.isHandsTogether) ...[
            const SizedBox(width: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
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
          const SizedBox(width: 8),
          // The direction the fingering shows (SA's scale segment)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Previous part of the scale',
            onPressed: _playing || segment <= lo ? null : () => _selectSegment(segment - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(hi - lo > 1 ? '$direction ($segment)' : direction),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Next part of the scale',
            onPressed: _playing || segment >= hi ? null : () => _selectSegment(segment + 1),
            icon: const Icon(Icons.chevron_right),
          ),
          _check('Fingers', _showFingers, (v) => setState(() => _showFingers = v)),
          _check('Metronome', _metronome, _playing ? null : (v) => setState(() => _metronome = v)),
          const SizedBox(width: 4),
          _playing
              ? FilledButton.icon(onPressed: _stopPlaying, icon: const Icon(Icons.stop), label: const Text('Stop'))
              : FilledButton.icon(
                  onPressed: _shown == null || _busy ? null : _play,
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Play ♩=${_shown?.minTempo ?? ''}'),
                ),
        ]),
      ],
    );
  }

  /// The controls to the right of a dropdown: shrunk to fit if the screen is too narrow for them (iPhone: 734 wide),
  /// rather than overflowing
  Widget _fitted(List<Widget> children) => Flexible(
    flex: 3,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );

  Widget _check(String label, bool value, void Function(bool)? onChanged) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Checkbox(
        visualDensity: VisualDensity.compact,
        value: value,
        onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
      ),
      Text(label),
    ],
  );

  Widget _listenRow() {
    final choices = <_ListenChoice>[
      const _ListenChoice(ListenWith.nothing),
      if (_services.pitch != null) const _ListenChoice(ListenWith.microphone),
      for (final d in _devices) _ListenChoice(ListenWith.midi, d),
    ];
    // The keyboard being listened to stays in the list even if it's missing from the latest refresh
    if (!choices.contains(_listen)) choices.add(_listen);
    final finding = _midi.bluetoothFinding;
    return Row(
      children: [
        const Text('Listen with: '),
        Expanded(
          flex: 2,
          child: DropdownButton<_ListenChoice>(
            isDense: true,
            isExpanded: true,
            value: _listen,
            items: [
              for (final c in choices)
                DropdownMenuItem(
                  value: c,
                  child: Text(c.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _busy
                ? null
                : (c) {
                    if (c != null && c != _listen) _chooseListen(c);
                  },
          ),
        ),
        _fitted([
          if (_midi.isSupported) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Refresh the MIDI keyboards',
              onPressed: _busy ? null : () => _refreshDevices(),
              icon: const Icon(Icons.refresh),
            ),
            if (finding != BluetoothFinding.none)
              TextButton.icon(
                onPressed: _busy ? null : _findBluetooth,
                icon: const Icon(Icons.bluetooth),
                label: Text(finding == BluetoothFinding.scan ? 'Find Bluetooth' : 'Bluetooth MIDI'),
              ),
            if (_listen.kind == ListenWith.midi)
              TextButton(onPressed: _checkWaiting ? null : _startCheck, child: const Text('Check')),
          ],
          _check('Screen keys play', _screenKeysPlay, (v) {
            setState(() => _screenKeysPlay = v);
            _log('Screen keys ${v ? 'play' : 'off'}');
          }),
        ]),
      ],
    );
  }

  Widget _statusLine() {
    final theme = Theme.of(context);
    final recent = _recent.map(
      (n) => '${midiName(n.midi)}${n.source == NoteSource.screen ? '' : '·${n.source.label}'}',
    );
    final text = [
      if (_midiProblem != null) 'MIDI: $_midiProblem',
      if (_status.isNotEmpty) _status,
      if (_recent.isNotEmpty) 'Played: ${recent.join(' ')}',
    ].join('   ');
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall);
  }
}
