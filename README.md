# Scales Academy Flutter (SAF)

Scales Academy for iOS, Android and the web, in Flutter. Dart project name: `scales_academy_flutter`.

## Structure
- `lib/platform/` - the only platform-specific code, behind interfaces (`platform_services.dart`):
  - `pitch/` - microphone pitch readings (Android: Kotlin YIN; iOS: AudioKit as in Scales Academy, or YIN; web: JavaScript YIN)
  - `sound/` - piano notes and metronome (flutter_soloud; iOS audio session via Swift)
  - `midi/` - MIDI keyboard input (Stage 4)
  - `recording/` - recording and playback (Stage 6)
- `lib/music/` - notes and names
- `lib/exercise/` - Scales Academy's note rules and scoring
- `lib/playback/` - tempo clock and scale player (shared timing engine)
- `lib/screens/` - screens (home menu, Listen, Sound)
- `assets/sounds/` - piano notes rendered from SA's SoundFonts (`tools/render_piano.py`) and SA's metronome clicks

## SoundFonts
Scales Academy's `.sf2` files are too large for GitHub (over 100 MB) and are not committed (see `.gitignore`).
Copy them into the project locally when needed.
