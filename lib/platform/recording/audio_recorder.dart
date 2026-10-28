/// Records the student playing and plays the recording back (Stage 6).
/// Each platform has its own implementation behind this interface.
abstract class AudioRecorder {
  /// Whether this platform can record
  bool get isSupported;

  Future<void> startRecording();

  /// Stops recording. Returns true if a recording is ready to play
  Future<bool> stopRecording();

  Future<void> playRecording();

  Future<void> stopPlayback();
}

/// Placeholder until Stage 6: no recording
class NoAudioRecorder implements AudioRecorder {
  @override
  bool get isSupported => false;
  @override
  Future<void> startRecording() async {}
  @override
  Future<bool> stopRecording() async => false;
  @override
  Future<void> playRecording() async {}
  @override
  Future<void> stopPlayback() async {}
}
