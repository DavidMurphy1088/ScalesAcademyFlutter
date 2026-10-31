import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../music/midi.dart';
import '../exercise/note_detector.dart';
import '../log/test_log.dart';
import '../platform/pitch/pitch_reading.dart';
import '../platform/pitch/pitch_source.dart';
import '../platform/platform_services.dart';
import 'common.dart';
import '../exercise/scale_scorer.dart';

/// Listens to the microphone and shows the notes detected, using Scales Academy's rules.
/// For testing pitch detection next to a piano.
class ListenPage extends StatefulWidget {
  const ListenPage({super.key});

  @override
  State<ListenPage> createState() => _ListenPageState();
}

class _ListenPageState extends State<ListenPage> {
  final PitchSource? _source = PlatformServices.instance.pitch;
  final NoteDetector _detector = NoteDetector();
  StreamSubscription<PitchReading>? _subscription;

  bool _listening = false;

  /// The chosen pitch detector (AudioKit or YIN on iPhone/iPad; YIN only on Android and web)
  late PitchDetectorOption _detectorOption =
      (_source?.detectors.isNotEmpty ?? false) ? _source!.detectors.first : yinDetector;
  /// Each detector's loudness filter for this run only. Nothing is saved: every launch starts with the defaults.
  final Map<String, double> _filterForDetector = {};
  String _status = 'Tap Start listening, then play single notes on the piano.';
  ReadingResult? _lastReading;
  NoteEvent? _lastNote;
  /// SA's scoring of a C major scale, right hand (see exercise/scale_scorer.dart)
  int _octaves = 1;
  late ScaleScorer _scorer = _makeScorer();

  /// 1 or 2 octaves start on middle C (C4); 3 octaves start an octave lower, on C3
  int get _startMidi => _octaves == 3 ? 48 : 60;
  ScaleScorer _makeScorer() => ScaleScorer(buildMajorScale(startMidi: _startMidi, octaves: _octaves));

  /// The test-wide settings that start each test log line from this screen
  List<String> get _logSettings => [
        'Listen',
        'C major RH $_octaves ${_octaves == 1 ? 'octave' : 'octaves'}',
        _detectorOption.label,
        'filter ${_detector.amplitudeFilter.toStringAsFixed(3)}',
        'readings in a row ${_detector.requiredCount}',
      ];

  void _log(String message) => TestLog.instance.add(_logSettings, message);

  void _chooseOctaves(int octaves) {
    setState(() {
      _octaves = octaves;
      _scorer = _makeScorer();
      _scoredLines.clear();
      _scaleEnded = false;
    });
  }

  /// After End Scale: for each line (in the order played), how many letter names it is from the
  /// previous line's note, if more than one, comparing letter names only (B and C are neighbours):
  /// whether the two notes sit side by side on the keyboard. D after C is fine; A after F is flagged.
  Map<ScoredLine, int> get _letterJumps {
    final jumps = <ScoredLine, int>{};
    for (var i = 1; i < _scoredLines.length; i++) {
      final distance = letterDistance(_scoredLines[i].verdict.midi, _scoredLines[i - 1].verdict.midi);
      if (distance > 1) jumps[_scoredLines[i]] = distance;
    }
    return jumps;
  }
  final List<ScoredLine> _scoredLines = [];

  /// End Scale was pressed: show the quietest and loudest notes
  bool _scaleEnded = false;
  int _readingCount = 0;

  /// Recent loudness readings (time, amplitude), for the "max in the last 3 s" figure
  static const _maxWindow = Duration(seconds: 3);
  final List<(DateTime, double)> _recentLoudness = [];

  /// Loudest reading heard in the last 3 seconds, or null if none
  double? get _maxRecentLoudness {
    final cutoff = DateTime.now().subtract(_maxWindow);
    double? max;
    for (final (time, amplitude) in _recentLoudness) {
      if (time.isAfter(cutoff) && (max == null || amplitude > max)) max = amplitude;
    }
    return max;
  }

  @override
  void initState() {
    super.initState();
    _applyDetectorFilter();
  }

  /// The chosen detector's filter: changed earlier in this run, otherwise its default
  void _applyDetectorFilter() {
    _detector.amplitudeFilter = _filterForDetector[_detectorOption.id] ?? _detectorOption.defaultAmplitudeFilter;
  }

  void _resetSettings() {
    setState(() {
      _filterForDetector.remove(_detectorOption.id);
      _detector.amplitudeFilter = _detectorOption.defaultAmplitudeFilter;
      _detector.requiredCount = NoteDetector.defaultRequiredCount;
    });
  }

  void _chooseDetector(PitchDetectorOption option) {
    setState(() {
      _detectorOption = option;
      _applyDetectorFilter();
      _detector.reset();
      _lastReading = null;
      _lastNote = null;
      _status = 'Detector: ${option.label}. Tap Start listening.';
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_listening) _source?.stop();
    super.dispose();
  }

  Future<void> _start() async {
    final source = _source;
    if (source == null) return;
    _detector.reset();
    _recentLoudness.clear();
    _restartScale();
    // Subscribe before starting so no readings are missed
    _subscription = source.readings.listen(_onReading);
    final result = await source.start(detectorId: _detectorOption.id);
    if (!mounted) return;
    setState(() {
      _listening = result.started;
      _status = result.detail;
    });
    _log('Start listening: ${result.started ? 'started' : 'did not start'} - ${result.detail}');
    if (!result.started) {
      await _subscription?.cancel();
      _subscription = null;
    }
  }

  Future<void> _stop() async {
    // Update the screen straight away; previously nothing changed until the platform confirmed the stop
    setState(() {
      _listening = false;
      _status = 'Stopping…';
    });
    await _subscription?.cancel();
    _subscription = null;
    try {
      // If the platform doesn't confirm within 3 seconds, say so instead of waiting forever
      await _source?.stop().timeout(const Duration(seconds: 3));
      if (mounted) setState(() => _status = 'Stopped');
    } on TimeoutException {
      if (mounted) setState(() => _status = 'Stop is taking too long: the microphone may still be on');
    } catch (e) {
      if (mounted) setState(() => _status = 'Problem stopping: $e');
    }
  }

  void _onReading(PitchReading reading) {
    final result = _detector.process(reading);
    final now = DateTime.now();
    _recentLoudness.add((now, reading.amplitude));
    _recentLoudness.removeWhere((r) => now.difference(r.$1) > _maxWindow);
    setState(() {
      _readingCount++;
      _lastReading = result;
      final note = result.note;
      if (note != null) {
        _lastNote = note;
        // As SA: every accepted reading is sent to the exercise as a noteOn and judged
        _addVerdict(_scorer.judge(note.midi), note.amplitude);
      }
    });
  }

  void _addVerdict(Verdict verdict, double loudness) {
    if (_scoredLines.isNotEmpty && _scoredLines.last.absorbs(verdict)) {
      _scoredLines.last.addReading(loudness);
    } else {
      _scoredLines.add(ScoredLine(verdict, loudness: loudness));
    }
  }

  /// End Scale: stop listening and show the quietest and loudest notes in the list
  Future<void> _endScale() async {
    if (_listening) await _stop();
    if (mounted) setState(() => _scaleEnded = true);
    // The whole End Scale report (as Copy full report), each line prefixed with this screen's settings
    if (_scoredLines.isNotEmpty) {
      _log('End Scale report:\n$_fullReportText');
    } else {
      _log('End Scale: no notes heard');
    }
  }

  /// One line of the End Scale summary
  String _loudnessLine(String label, ScoredLine line) =>
      '$label: ${midiName(line.verdict.midi)}  peak ${line.peakLoudness.toStringAsFixed(3)}'
      '  (first reading ${line.firstLoudness.toStringAsFixed(3)}, ${line.readings} '
      '${line.readings == 1 ? 'reading' : 'readings'}, ${line.verdict.kind.name})';

  /// The quietest and loudest notes, as copyable text
  String get _minMaxText {
    final quietest = _scoredLines.reduce((a, b) => b.peakLoudness < a.peakLoudness ? b : a);
    final loudest = _scoredLines.reduce((a, b) => b.peakLoudness > a.peakLoudness ? b : a);
    return '${_loudnessLine('Quietest note', quietest)}\n${_loudnessLine('Loudest note', loudest)}';
  }

  /// The whole End Scale report as plain text, in the order the notes were played
  String get _fullReportText {
    final jumps = _letterJumps;
    final b = StringBuffer()
      ..writeln('C major, $_octaves ${_octaves == 1 ? 'octave' : 'octaves'}, right hand, from ${midiName(_startMidi)} (scored as SA)')
      ..writeln('Detector: ${_detectorOption.label}   Loudness filter: ${_detector.amplitudeFilter.toStringAsFixed(3)}'
          '   Readings in a row: ${_detector.requiredCount}')
      ..writeln(_scorer.completed ? 'Completed' : 'Not completed: next expected '
          '${_scorer.nextExpected == null ? '-' : midiName(_scorer.nextExpected!)}')
      ..writeln('Progress ${_scorer.progress} / ${_scorer.notes.length}   Correct ${_scorer.totalCorrect}   '
          'Wrong ${_scoredLines.where((l) => l.verdict.kind == VerdictKind.wrong).length}'
          ' (${_scorer.wrongReadings} readings)')
      ..writeln(_minMaxText)
      ..writeln(jumps.isEmpty
          ? 'No note moved more than one letter name from the note before it'
          : '${jumps.length} ${jumps.length == 1 ? 'place' : 'places'} where a note moved more than one letter name '
              'from the note before it (marked >>)')
      ..writeln()
      ..writeln('Notes in the order played:');
    for (var i = 0; i < _scoredLines.length; i++) {
      final line = _scoredLines[i];
      final v = line.verdict;
      final mark = switch (v.kind) {
        VerdictKind.correct => 'OK   ',
        VerdictKind.wrong => 'WRONG',
        VerdictKind.ignored => 'ign  ',
      };
      final jump = jumps[line];
      b.writeln('${jump != null ? '>>' : '  '} ${(i + 1).toString().padLeft(3)}. $mark ${v.description}'
          '${line.readings > 1 ? '  (x${line.readings} readings)' : ''}'
          '  peak ${line.peakLoudness.toStringAsFixed(3)}'
          '${jump != null && i > 0 ? '  [$jump letter names from ${midiName(_scoredLines[i - 1].verdict.midi)}]' : ''}');
    }
    return b.toString();
  }

  Future<void> _copyFullReport() async {
    await Clipboard.setData(ClipboardData(text: _fullReportText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Full report copied')));
  }

  /// Quietest and loudest notes (selectable; the full report has its own Copy button)
  Widget _minMaxSummary(ThemeData theme) {
    final text = _minMaxText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectableText(text, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  ScoredLine? _previousLine(ScoredLine line) {
    final i = _scoredLines.indexOf(line);
    return i > 0 ? _scoredLines[i - 1] : null;
  }

  void _restartScale() {
    _scorer.reset();
    _scoredLines.clear();
    _scaleEnded = false;
  }

  Widget _scoredLineTile(ScoredLine line, ThemeData theme, {int? letterJump, ScoredLine? previous}) {
    final v = line.verdict;
    final (IconData icon, Color color) = switch (v.kind) {
      VerdictKind.correct => (Icons.check_circle, Colors.green),
      VerdictKind.wrong => (Icons.cancel, Colors.red),
      VerdictKind.ignored => (Icons.remove_circle_outline, Colors.grey),
    };
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${v.description}${line.readings > 1 ? '  (×${line.readings} readings)' : ''}'
                '  · peak ${line.peakLoudness.toStringAsFixed(3)}',
                style: v.kind == VerdictKind.ignored ? theme.textTheme.bodySmall : null,
              ),
              if (letterJump != null && previous != null)
                Text(
                  '↕ $letterJump letter names from the previous note, ${midiName(previous.verdict.midi)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ],
    );
    // Flagged after End Scale: highlighted in amber
    if (letterJump != null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.25),
          border: Border.all(color: Colors.orange),
          borderRadius: BorderRadius.circular(6),
        ),
        child: row,
      );
    }
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: row);
  }

  String _statusText(ReadingStatus status) {
    switch (status) {
      case ReadingStatus.accepted:
        return 'accepted';
      case ReadingStatus.belowAmplitudeFilter:
        return 'too quiet';
      case ReadingStatus.countTooLow:
        return 'waiting for repeat';
      case ReadingStatus.noPitch:
        return 'no clear pitch';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_source == null) {
      return Scaffold(
        appBar: saAppBar(context, 'SA Flutter'),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Listening is available on Android, iPhone/iPad and the web.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      );
    }

    final reading = _lastReading;
    final note = _lastNote;
    final jumps = _scaleEnded ? _letterJumps : const <ScoredLine, int>{};
    final theme = Theme.of(context);

    return Scaffold(
      appBar: saAppBar(context, 'SA Flutter – Listen'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Scale length: 1 or 2 octaves from C4, 3 octaves from C3. Changing it restarts the scale
            Center(
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(value: 1, label: Text('1 octave')),
                  ButtonSegment<int>(value: 2, label: Text('2 octaves')),
                  ButtonSegment<int>(value: 3, label: Text('3 octaves')),
                ],
                selected: {_octaves},
                onSelectionChanged: (selection) => _chooseOctaves(selection.first),
              ),
            ),
            const SizedBox(height: 12),
            // Detector choice: shown as a switch when there is more than one (iPhone/iPad)
            if (_source.detectors.length > 1) ...[
              Center(
                child: SegmentedButton<String>(
                  segments: [
                    for (final option in _source.detectors)
                      ButtonSegment<String>(value: option.id, label: Text(option.label)),
                  ],
                  selected: {_detectorOption.id},
                  // Can only be changed while not listening
                  onSelectionChanged: _listening
                      ? null
                      : (selection) => _chooseDetector(
                            _source.detectors.firstWhere((o) => o.id == selection.first),
                          ),
                ),
              ),
              const SizedBox(height: 12),
            ] else
              Center(child: Text('Detector: ${_detectorOption.label}', style: theme.textTheme.bodySmall)),
            // While listening, the first note of the scale is shown beside the button
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _listening ? _stop : _start,
                  icon: Icon(_listening ? Icons.stop : Icons.mic),
                  label: Text(_listening ? 'Stop listening' : 'Start listening'),
                ),
                if (_listening) ...[
                  const SizedBox(width: 12),
                  Text('First note: ${midiName(_scorer.notes.first)}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(_status, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            const SizedBox(height: 24),

            // Left: the note accepted by the Scales Academy rules. Right: the live reading, for tuning
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              note == null ? '–' : midiName(note.midi),
                              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(note == null ? 'No note yet' : 'MIDI ${note.midi}', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Latest reading (#$_readingCount)', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          Text(reading == null
                              ? '–'
                              : reading.reading.hasPitch
                                  ? '${reading.reading.frequency.toStringAsFixed(1)} Hz  →  ${midiName(reading.midi)}   '
                                      'clarity ${reading.reading.clarity.toStringAsFixed(2)}'
                                  : 'no pitch'),
                          Text(reading == null ? '' : 'Status: ${_statusText(reading.status)}'),
                          const SizedBox(height: 8),
                          Text('Loudness ${reading == null ? '–' : reading.reading.amplitude.toStringAsFixed(3)}'
                              '   (filter ${_detector.amplitudeFilter.toStringAsFixed(3)})'),
                          LinearProgressIndicator(
                            value: reading == null ? 0 : (reading.reading.amplitude / 0.2).clamp(0.0, 1.0),
                          ),
                          const SizedBox(height: 4),
                          Text('Max loudness, last 3 s: ${_maxRecentLoudness?.toStringAsFixed(3) ?? '–'}'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Settings matching Scales Academy's detection gates
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Loudness filter for ${_detectorOption.label}: ${_detector.amplitudeFilter.toStringAsFixed(3)}  (SA default 0.030)'),
                    Slider(
                      value: _detector.amplitudeFilter.clamp(0.0, 0.07),
                      min: 0,
                      max: 0.07,
                      divisions: 70, // steps of 0.001
                      onChanged: (v) => setState(() {
                        _detector.amplitudeFilter = v;
                        // Kept for this run only, per detector
                        _filterForDetector[_detectorOption.id] = v;
                      }),
                    ),
                    Row(
                      children: [
                        Expanded(child: Text('Readings in a row needed: ${_detector.requiredCount}  (SA default 2)')),
                        IconButton(
                          onPressed: _detector.requiredCount > 1
                              ? () => setState(() => _detector.requiredCount--)
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        IconButton(
                          onPressed: _detector.requiredCount < 5
                              ? () => setState(() => _detector.requiredCount++)
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _resetSettings,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset to defaults'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            // SA's judgement of each note: two-octave C major, right hand, from C4
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('C major, $_octaves ${_octaves == 1 ? 'octave' : 'octaves'}, right hand, '
                        'from ${midiName(_startMidi)} (scored as SA)', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(_scorer.completed
                        ? 'Completed'
                        : 'Next expected: ${_scorer.nextExpected == null ? '–' : midiName(_scorer.nextExpected!)}'),
                    Text('Progress ${_scorer.progress} / ${_scorer.notes.length}   '
                        'Correct ${_scorer.totalCorrect}   '
                        'Wrong ${_scoredLines.where((l) => l.verdict.kind == VerdictKind.wrong).length}'
                        ' (${_scorer.wrongReadings} readings)'),
                    const SizedBox(height: 8),
                    // After End Scale: the quietest and loudest notes in the list, by each note's peak loudness
                    if (_scaleEnded && _scoredLines.isNotEmpty) ...[

                      _minMaxSummary(theme),
                      Text('Loudness filter in use: ${_detector.amplitudeFilter.toStringAsFixed(3)}',
                          style: theme.textTheme.bodySmall),
                      Text(
                        jumps.isEmpty
                            ? 'No note moved more than one letter name from the note before it'
                            : '${jumps.length} ${jumps.length == 1 ? 'place' : 'places'} where a note moved more than '
                                'one letter name from the note before it (highlighted below)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: jumps.isEmpty ? null : Colors.orange.shade900, fontWeight: FontWeight.w600),
                      ),
                      const Divider(),
                    ],
                    if (_scoredLines.isEmpty)
                      Text('Play the scale: notes appear here as SA would judge them.', style: theme.textTheme.bodySmall)
                    else
                      for (final line in _scoredLines.reversed)
                        _scoredLineTile(
                          line,
                          theme,
                          // Letter-name jumps are only highlighted after End Scale
                          letterJump: _scaleEnded ? jumps[line] : null,
                          previous: _scaleEnded ? _previousLine(line) : null,
                        ),
                    // Wrap so the three buttons move to a second line on narrow phones instead of overflowing
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(_restartScale),
                          icon: const Icon(Icons.replay),
                          label: const Text('Restart scale'),
                        ),
                        TextButton.icon(
                          onPressed: _scoredLines.isEmpty ? null : _endScale,
                          icon: const Icon(Icons.flag),
                          label: const Text('End Scale'),
                        ),
                        // After End Scale: copy the whole report
                        if (_scaleEnded && _scoredLines.isNotEmpty)
                          FilledButton.tonalIcon(
                            onPressed: _copyFullReport,
                            icon: const Icon(Icons.copy_all),
                            label: const Text('Copy full report'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
