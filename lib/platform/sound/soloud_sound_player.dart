import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'sound_player.dart';

/// Sound on Android, iOS and the web through flutter_soloud (one Dart API for all three).
///
/// Piano notes are short recordings rendered from Scales Academy's SoundFonts (tools/render_piano.py):
/// one file per MIDI note, 2.5 s, mono, velocity 64 as SA plays. Releasing a note fades it out.
class SoloudSoundPlayer implements SoundPlayer {
  static const _pianos = [
    // The first entry is the default piano (Yamaha, David 29 Oct 2026)
    PianoSound('yamaha', 'Yamaha', 'assets/sounds/piano_yamaha'),
    PianoSound('steinway', 'Steinway (SA)', 'assets/sounds/piano_steinway'),
  ];
  static const lowestMidi = 21; // A0
  static const highestMidi = 108; // C8

  /// How long a released note takes to fade out
  static const release = Duration(milliseconds: 150);

  final _notes = <int, AudioSource>{};
  final _sounding = <int, SoundHandle>{};
  AudioSource? _clickLow;
  AudioSource? _clickHigh;
  PianoSound _piano = _pianos.first;
  bool _ready = false;

  @override
  double pianoVolume = 1.0;
  @override
  double clickVolume = 0.5;

  SoLoud get _soloud => SoLoud.instance;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// flutter_soloud's guidance: load assets with LoadMode.disk on the web, memory elsewhere
  LoadMode get _mode => kIsWeb ? LoadMode.disk : LoadMode.memory;

  @override
  List<PianoSound> get pianos => _pianos;
  @override
  PianoSound get piano => _piano;
  @override
  bool get isReady => _ready;

  @override
  Future<Duration> init({String? pianoId}) async {
    final timer = Stopwatch()..start();
    if (!_soloud.isInitialized) {
      if (_isIOS) await _configureIOSAudioSession();
      // init() is not repeatable (it would unload everything), hence the isInitialized check.
      // iOS: 48 kHz to match the hardware rate Scales Academy uses (see SA Notes/AudioSession_iPadPlaybackScratch.md)
      await _soloud.init(sampleRate: _isIOS ? 48000 : 44100, bufferSize: 1024);
      // Default is 16 voices; legato scales overlap fading notes, so allow more
      _soloud.setMaxActiveVoiceCount(64);
    }
    _clickLow ??= await _soloud.loadAsset('assets/sounds/metronome/click_low.wav', mode: _mode);
    _clickHigh ??= await _soloud.loadAsset('assets/sounds/metronome/click_high.wav', mode: _mode);
    await _loadPiano(pianoId ?? _piano.id);
    _ready = true;
    return timer.elapsed;
  }

  @override
  Future<Duration> selectPiano(String pianoId) async {
    final timer = Stopwatch()..start();
    await _loadPiano(pianoId);
    return timer.elapsed;
  }

  Future<void> _loadPiano(String pianoId) async {
    final chosen = _pianos.firstWhere((p) => p.id == pianoId, orElse: () => _pianos.first);
    if (chosen.id == _piano.id && _notes.isNotEmpty) return;
    allNotesOff();
    for (final source in _notes.values) {
      await _soloud.disposeSource(source);
    }
    _notes.clear();
    final midis = [for (var m = lowestMidi; m <= highestMidi; m++) m];
    final sources = await Future.wait(
      midis.map((m) => _soloud.loadAsset('${chosen.assetFolder}/$m.ogg', mode: _mode)),
    );
    for (var i = 0; i < midis.length; i++) {
      _notes[midis[i]] = sources[i];
    }
    _piano = chosen;
  }

  /// iOS only: set Scales Academy's audio session (SoLoud leaves the session to the app; without this
  /// the silent switch mutes the app). Done in Swift: PitchChannel.swift "configureSession".
  Future<void> _configureIOSAudioSession() async {
    try {
      await const MethodChannel('fl/pitch/control').invokeMethod('configureSession');
    } catch (e) {
      debugPrint('SoloudSoundPlayer: audio session not configured: $e');
    }
  }

  @override
  void noteOn(int midi) {
    if (!_ready) return;
    final source = _notes[midi];
    if (source == null) return;
    final previous = _sounding.remove(midi);
    if (previous != null) _fadeOut(previous);
    _sounding[midi] = _soloud.play(source, volume: pianoVolume);
  }

  @override
  void noteOff(int midi) {
    final handle = _sounding.remove(midi);
    if (handle != null) _fadeOut(handle);
  }

  @override
  void allNotesOff() {
    for (final handle in _sounding.values) {
      _fadeOut(handle);
    }
    _sounding.clear();
  }

  void _fadeOut(SoundHandle handle) {
    try {
      if (!_soloud.getIsValidVoiceHandle(handle)) return; // the note had already finished
      _soloud.fadeVolume(handle, 0, release);
      _soloud.scheduleStop(handle, release);
    } catch (e) {
      debugPrint('SoloudSoundPlayer: fade out failed: $e');
    }
  }

  @override
  void click({bool accent = false}) {
    if (!_ready) return;
    final source = accent ? _clickHigh : _clickLow;
    if (source != null) _soloud.play(source, volume: clickVolume);
  }

  @override
  Future<void> dispose() async {
    allNotesOff();
  }
}
