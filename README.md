# Scales Academy Flutter (SAF)

Scales Academy for iOS, Android and the web, in Flutter. Dart project name: `scales_academy_flutter`.

## Structure
- `lib/platform/` - the only platform-specific code, behind interfaces (`platform_services.dart`):
  - `pitch/` - microphone pitch readings (Android: Kotlin YIN; iOS: AudioKit as in Scales Academy, or YIN; web: JavaScript YIN)
  - `sound/` - piano notes and metronome (flutter_soloud; iOS audio session via Swift)
  - `midi/` - MIDI keyboard input (Stage 4)
  - `recording/` - recording and playback (Stage 6)
  - `score/` - the score view: OSMD in a web view on Android/iOS (`webview_flutter`), straight into the page on the web
- `lib/score/` - the score description (key, staves, notes with their spelling) sent to the score page;
  `scale_score.dart` makes it from a scale
- `lib/music/` - notes and names; `scale.dart` - port of SA's scale model (all scale types: notes, values, fingering,
  finger-break colours, segments); `scale_spelling.dart` - key signature and note spelling; `abrsm_grade5.dart` - SA's
  ABRSM Grade 5 list
- `lib/exercise/` - Scales Academy's note rules and scoring
- `lib/playback/` - tempo clock and scale player (shared timing engine)
- `lib/screens/` - screens (home menu, Listen, Sound, Score)
- `assets/score/` - the score page shared by all platforms: `score.js` (MusicXML with SA's layout rules, drawing,
  SA's green ring), `score.html` (web view page), OpenSheetMusicDisplay 2.2.1 (`osmd.min.js`, BSD-3)
- `assets/sounds/` - piano notes rendered from SA's SoundFonts (`tools/render_piano.py`) and SA's metronome clicks

## SoundFonts
Scales Academy's `.sf2` files are too large for GitHub (over 100 MB) and are not committed (see `.gitignore`).
Copy them into the project locally when needed.

## Checking the scale model against SA
`dart run tools/check_scales.dart` compares SAF's scales with SA's, note by note, using
`test/sa_reference/abrsm_grade5.json`, written by SA's test "Export for SAF" (`ScalesAcademyTests/ExportForSAFTests.swift`,
run on an iOS Simulator).
