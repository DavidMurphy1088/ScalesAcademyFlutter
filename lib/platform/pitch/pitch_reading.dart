/// One pitch estimate from the microphone, made from one block of 4096 samples (about 0.09 s).
/// Equivalent to one call of AudioKit's PitchTap in Scales Academy.
class PitchReading {
  /// Frequency in Hz, or -1 if no clear pitch was found
  final double frequency;

  /// Loudness (RMS, 0..1)
  final double amplitude;

  /// How clear the pitch was, 0..1 (Android YIN only; not used for detection)
  final double clarity;

  const PitchReading({required this.frequency, required this.amplitude, this.clarity = 0});

  bool get hasPitch => frequency > 0;
}
