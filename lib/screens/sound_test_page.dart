import 'package:flutter/material.dart';

import '../exercise/scale_scorer.dart';
import '../log/test_log.dart';
import '../music/midi.dart';
import '../platform/platform_services.dart';
import '../platform/sound/sound_player.dart';
import '../playback/scale_player.dart';
import 'common.dart';

/// Stage 1 test screen: piano notes, a C major scale at a chosen tempo, and the metronome
class SoundTestPage extends StatefulWidget {
  const SoundTestPage({super.key});

  @override
  State<SoundTestPage> createState() => _SoundTestPageState();
}

enum _Playing { nothing, scale, metronome }

class _SoundTestPageState extends State<SoundTestPage> {
  final SoundPlayer _sound = PlatformServices.instance.sound;
  late final ScalePlayer _player = ScalePlayer(_sound)
    ..onNote = _onScaleNote
    ..onFinished = _onScaleFinished;

  bool _starting = false;
  String _status = 'Tap Start sound (browsers only allow sound after a tap).';

  // Note buttons
  int _octave = 4;
  final Set<int> _keysDown = {};

  // Scale settings (as SA: quavers, count-in of 4 beats)
  int _octaves = 1;
  int _tempo = 120;
  bool _metronome = true;
  bool _countIn = true;

  _Playing _playing = _Playing.nothing;
  int? _currentIndex;
  int? _currentMidi;
  String? _timing;

  int get _startMidi => _octaves == 3 ? 48 : 60;

  /// The test-wide settings that start each test log line from this screen
  List<String> get _logSettings => [
        'Sound',
        _sound.piano.label,
        'C major RH $_octaves ${_octaves == 1 ? 'octave' : 'octaves'}',
        '♩=$_tempo',
        'metronome ${_metronome ? 'on' : 'off'}',
        'count-in ${_countIn ? 'on' : 'off'}',
      ];

  void _log(String message) => TestLog.instance.add(_logSettings, message);
  List<int> get _scaleNotes => buildMajorScale(startMidi: _startMidi, octaves: _octaves);

  @override
  void dispose() {
    _player.stop();
    super.dispose();
  }

  Future<void> _startSound() async {
    setState(() {
      _starting = true;
      _status = 'Loading ${_sound.piano.label}…';
    });
    try {
      final took = await _sound.init();
      if (!mounted) return;
      setState(() => _status = 'Ready: ${_sound.piano.label} loaded in ${took.inMilliseconds} ms');
      _log('Start sound: $_status');
    } catch (e) {
      if (mounted) setState(() => _status = 'Sound could not start: $e');
      _log('Sound could not start: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _choosePiano(String id) async {
    _stopPlaying();
    setState(() {
      _starting = true;
      _status = 'Loading…';
    });
    try {
      final took = await _sound.selectPiano(id);
      if (mounted) setState(() => _status = 'Ready: ${_sound.piano.label} loaded in ${took.inMilliseconds} ms');
      _log('Piano chosen: $_status');
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not load: $e');
      _log('Piano could not load: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _keyDown(int midi) {
    _sound.noteOn(midi);
    setState(() => _keysDown.add(midi));
  }

  void _keyUp(int midi) {
    _sound.noteOff(midi);
    setState(() => _keysDown.remove(midi));
  }

  void _playScale() {
    _player.play(ScalePlan(
      notes: _scaleNotes,
      tempo: _tempo,
      leadInBeats: _countIn ? 4 : 0,
      metronome: _metronome,
    ));
    setState(() {
      _playing = _Playing.scale;
      _currentIndex = null;
      _currentMidi = null;
      _timing = null;
    });
  }

  void _startMetronome() {
    _player.play(ScalePlan.metronomeOnly(tempo: _tempo));
    setState(() {
      _playing = _Playing.metronome;
      _timing = null;
    });
  }

  void _stopPlaying() {
    if (_playing == _Playing.nothing) return;
    final what = _playing == _Playing.metronome ? 'Metronome only' : 'Play scale (stopped early)';
    _player.stop();
    setState(() {
      _playing = _Playing.nothing;
      _timing = _timingText();
    });
    _log('$what: ${_timing!.isEmpty ? 'no timing yet' : _timing}');
  }

  void _onScaleNote(int index, int midi) {
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      _currentMidi = midi;
    });
  }

  void _onScaleFinished() {
    if (!mounted) return;
    setState(() {
      _playing = _Playing.nothing;
      _timing = _timingText();
    });
    _log('Play scale: ${_timing!.isEmpty ? 'no timing yet' : _timing}');
  }

  /// How punctual the timing engine was on this device
  String _timingText() {
    final clock = _player.clock;
    if (clock.ticksMeasured == 0) return '';
    return 'Timing over ${clock.ticksMeasured} ticks: average ${clock.averageLateMs.toStringAsFixed(1)} ms late, '
        'worst ${clock.worstLateMs.toStringAsFixed(1)} ms';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _sound.isReady;
    return Scaffold(
      appBar: saAppBar(context, 'SA Flutter – Sound'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Start and piano choice
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!ready)
                  FilledButton.icon(
                    onPressed: _starting ? null : _startSound,
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Start sound'),
                  )
                else
                  SegmentedButton<String>(
                    segments: [
                      for (final p in _sound.pianos) ButtonSegment<String>(value: p.id, label: Text(p.label)),
                    ],
                    selected: {_sound.piano.id},
                    onSelectionChanged: _starting ? null : (s) => _choosePiano(s.first),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_status, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),

            // Note buttons: press and hold to hear a note
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Notes - press and hold', style: theme.textTheme.titleSmall)),
                        IconButton(
                          onPressed: _octave > 1 ? () => setState(() => _octave--) : null,
                          icon: const Icon(Icons.remove),
                        ),
                        Text('Octave $_octave'),
                        IconButton(
                          onPressed: _octave < 7 ? () => setState(() => _octave++) : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    _noteRow(const [1, 3, 6, 8, 10], ready, theme), // sharps
                    const SizedBox(height: 6),
                    _noteRow(const [0, 2, 4, 5, 7, 9, 11, 12], ready, theme), // naturals, up to the next C
                  ],
                ),
              ),
            ),

            // Scale and metronome
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('C major scale, right hand, played as SA plays it (quavers, legato)',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment<int>(value: 1, label: Text('1 octave')),
                        ButtonSegment<int>(value: 2, label: Text('2 octaves')),
                        ButtonSegment<int>(value: 3, label: Text('3 octaves')),
                      ],
                      selected: {_octaves},
                      onSelectionChanged:
                          _playing == _Playing.nothing ? (s) => setState(() => _octaves = s.first) : null,
                    ),
                    const SizedBox(height: 8),
                    Text('Tempo ♩ = $_tempo'),
                    Slider(
                      value: _tempo.toDouble(),
                      min: 40,
                      max: 160,
                      divisions: 120,
                      label: '$_tempo',
                      onChanged: _playing == _Playing.nothing ? (v) => setState(() => _tempo = v.round()) : null,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (label, tempo) in const [('Grade 5 scales 120', 120), ('Grade 5 arpeggios 88', 88), ('60', 60)])
                          ActionChip(
                            label: Text(label),
                            onPressed: _playing == _Playing.nothing ? () => setState(() => _tempo = tempo) : null,
                          ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Metronome while the scale plays'),
                      value: _metronome,
                      onChanged: _playing == _Playing.nothing ? (v) => setState(() => _metronome = v) : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Count-in of 4 beats (as SA)'),
                      value: _countIn,
                      onChanged: _playing == _Playing.nothing ? (v) => setState(() => _countIn = v) : null,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_playing == _Playing.nothing) ...[
                          FilledButton.icon(
                            onPressed: ready ? _playScale : null,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Play scale'),
                          ),
                          OutlinedButton.icon(
                            onPressed: ready ? _startMetronome : null,
                            icon: const Icon(Icons.timer),
                            label: const Text('Metronome only'),
                          ),
                        ] else
                          FilledButton.icon(
                            onPressed: _stopPlaying,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                          ),
                        if (_playing == _Playing.scale)
                          Text(
                            _currentMidi == null
                                ? 'Count-in…'
                                : '${midiName(_currentMidi!)}  (${_currentIndex! + 1} / ${_scaleNotes.length})',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                    if (_timing != null && _timing!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SelectableText(_timing!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),

            // Volumes
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Piano volume ${(_sound.pianoVolume * 100).round()}%'),
                    Slider(value: _sound.pianoVolume, onChanged: (v) => setState(() => _sound.pianoVolume = v)),
                    Text('Metronome volume ${(_sound.clickVolume * 100).round()}%'),
                    Slider(value: _sound.clickVolume, onChanged: (v) => setState(() => _sound.clickVolume = v)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A row of note buttons for the chosen octave. [semitones] are above C of that octave.
  Widget _noteRow(List<int> semitones, bool ready, ThemeData theme) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in semitones)
          _NoteButton(
            midi: (_octave + 1) * 12 + s,
            enabled: ready,
            down: _keysDown.contains((_octave + 1) * 12 + s),
            onDown: _keyDown,
            onUp: _keyUp,
          ),
      ],
    );
  }
}

/// A note button that sounds on finger down and releases on finger up (not on tap, which waits for the release)
class _NoteButton extends StatelessWidget {
  final int midi;
  final bool enabled;
  final bool down;
  final void Function(int midi) onDown;
  final void Function(int midi) onUp;

  const _NoteButton({required this.midi, required this.enabled, required this.down, required this.onDown, required this.onUp});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sharp = midiName(midi).contains('#');
    return Listener(
      onPointerDown: enabled ? (_) => onDown(midi) : null,
      onPointerUp: enabled ? (_) => onUp(midi) : null,
      onPointerCancel: enabled ? (_) => onUp(midi) : null,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: !enabled
              ? scheme.surfaceContainerHighest
              : down
                  ? scheme.primary
                  : sharp
                      ? scheme.inverseSurface
                      : scheme.surface,
          border: Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          midiName(midi),
          style: TextStyle(
            color: down ? scheme.onPrimary : (sharp && enabled ? scheme.onInverseSurface : scheme.onSurface),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
