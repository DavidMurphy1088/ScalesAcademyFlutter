# SA Flutter (SAF) - project plan and decisions

Read this first in every session. Update the **Status** and **Test log** sections at the end of each stage.

## Names and places
- **SA** = Scales Academy, the live Swift iOS app: `/Users/davidmurphy/Projects/ScalesAcademy` (GitHub `DavidMurphy1088/ScalesTrainer`)
- **FL** = FlutterTest / "Scales Academy Test", the pitch-detection trial: `/Volumes/DynabookSSD/Projects/FlutterTest`
  **FL is frozen (28 Oct 2026): don't change it; read it only if needed. All work and testing is in SAF.**
- **SAFlutter** (also "SAF") = this project, app name "SA Flutter": `/Volumes/DynabookSSD/Projects/ScalesAcademyFlutter`, Dart name `scales_academy_flutter`,
  GitHub `DavidMurphy1088/ScalesAcademyFlutter`, branch `main`
- App IDs: Android `nz.co.musicmastereducation.scales_academy_flutter`, iOS `nz.co.musicmastereducation.scalesAcademyFlutter`
- Run: `./run.sh` in the project folder (1 Android, 2 Web, 3 iOS).
- Devices: Samsung SM A075F `R83YC0ACRMZ`; iPhone `00008110-000A4D263E40A01E`; iPad `00008101-001A10983485001E`; `chrome`

## Decisions (agreed with David, Oct 2026)
1. **One Flutter codebase for iOS, Android and web**; it will eventually replace the Swift app. Platform-specific code
   (pitch detection, sound, MIDI, recording) sits behind Dart interfaces in `lib/platform/`; the rest of the app never sees it.
2. **Android acoustic listening is good enough** (FL tests). Android may use its own parameters (e.g. loudness filter)
   to be as accurate as possible. Support Android generally.
3. **Web**: a demo at first, but make no structural decision that would stop it becoming a product. No web subscriptions for now.
4. **Licence**: unrestricted on Android and web for now. Ignore subscriptions, badges and email for now.
5. **Sound, Play Along, recording**: do the best possible; David tests when finished.
6. **MIDI**: offer whatever the platform supports (Android/iOS USB+Bluetooth, Web MIDI in Chrome/Edge, none in Safari).
7. **Score rendering: OpenSheetMusicDisplay (OSMD)** for all score rendering, not a port of SA's Swift staff code.
   **Keyboard**: purpose-built Dart widget with SA's key colours (existing Flutter keyboard packages can't colour keys).
   **On-screen keyboard input**, so students can practise without a piano.
8. **No user data needs to be retained** from SA. (When SAF replaces SA on iOS: keep SA's bundle ID and subscription
   product IDs so subscribers keep access.)
9. **No automated tests required for now** (existing Dart unit tests kept).
10. **Scope for first test**: Grade 5 only (ABRSM); placeholder user/grade structure; Practice Chart / Choose Exercise
    style navigation and SA's **Spin Wheel**; **testable Follow and Lead** is the priority.
11. **Git**: commit at the end of each stage (after it builds and runs for David); David pushes from his Terminal.
    `.sf2` SoundFonts are not committed (SA's Steinway_D.sf2 234 MB and FluidGM_Bank_0.sf2 148 MB exceed GitHub's 100 MB limit;
    also too large for web and probably for the Play Store - choosing smaller sounds is part of Stage 1).

## Stages (riskiest first; each ends with something David can run)
- **Stage 0 - Skeleton** (done 28 Oct 2026): project from FL, renamed; `lib/platform/` interfaces (pitch working; sound, MIDI,
  recording placeholders); git. Test: builds on Samsung, iPhone, Chrome; listening works as in FL.
- **Stage 1 - Sound and metronome** (high risk; done 29 Oct 2026):
  - **Changed from the outline:** one sound engine for all three platforms, **flutter_soloud 5.2.1** (pinned), instead of
    flutter_midi_pro (no web) plus a separate JavaScript SoundFont player. No platform code except iOS's audio session.
  - Piano notes are **pre-rendered from SA's SoundFonts** (tools/render_piano.py): one 2.5 s mono Ogg file per MIDI note 21-108,
    velocity 64 as SA plays. SA's Steinway_D.sf2 (234 MB) becomes 1.5 MB, so SA's own piano sound works on Android and web.
    Yamaha Grand Lite (+12 dB) is the default piano (David, 29 Oct 2026); SA's Steinway is the second choice. Released notes fade out over 150 ms. Pitch checked within a few cents.
  - SA's metronome: low click every beat (SA uses only the low click), count-in 4 beats; clicks converted from AIFF to WAV.
  - SA's playback rule: tempo = crotchet beats/min; scale notes are quavers (2 per beat; triplets 3 for broken chords);
    legato (each note until the next); notes per click from the time signature (compound time 3).
  - Timing: `lib/playback/tempo_clock.dart` times every tick from the start (no drift), as SA's Metronome; reports lateness.
  - iOS: SoLoud leaves the audio session to the app, so the Dart player calls Swift `configureSession` (SA's playAndRecord
    session, 48 kHz) first; without it the silent switch mutes the app. Engine runs at 48 kHz on iOS, 44.1 kHz elsewhere.
  - To check later: SoLoud and the microphone together on iOS (Stages 5-6) - both use the same audio session.
  - Licence question for David: SA's Steinway_D.sf2 is described in SA's code as "Logic Pro Steinway D". If it was taken from
    Logic Pro, check its licence allows distributing it (or recordings of it) inside an app - this applies to SA already.
- **Stage 2 - Score via OSMD** (high risk): MusicXML for Grade 5 scales; web view on phones; live note highlighting at 120 bpm.
  Fallback: colour SVG directly, or draw the staff in Dart.
- **Stage 3 - Scale model, Grade 5**: port SA `Scale.swift`; compare note lists with SA (a test in SA can print them).
- **Stage 4 - Keyboard and inputs**: Dart keyboard; microphone, MIDI and on-screen touch feeding one note stream.
- **Stage 5 - Follow and Lead**: port SA `ExerciseHandler`; compare with SA on iPhone at the piano; Samsung; MIDI; touch.
- **Stage 6 - Recording, playback, Play Along** (high risk, lower priority). Apply SA `Notes/AudioSession_iPadPlaybackScratch.md`.
- **Stage 7 - Placeholder navigation**: Grade 5 user, Practice Chart / Choose Exercise, Spin Wheel, scale screen.
- **Stage 8 - Web check** (Chrome, Safari, Android Chrome).
- Estimate: about 13-18 sessions.

## Ideas for later
- Move YIN pitch detection into Dart so each platform only captures audio blocks (AudioKit stays native on iOS).
- Neural pitch detectors (e.g. SwiftF0, FCNF0++/penn) if YIN/AudioKit are not accurate enough.

## SA behaviour to keep in mind (from SA code)
- Microphone note rules: loudness filter (SA fixed 0.03, AudioKit scale), same note name in 2 readings in a row, ~10 readings/s.
- ExerciseHandler: notes > 3 semitones outside the scale range ignored; lookahead 2 (acoustic) / 1 (MIDI, or at top of scale);
  octave tolerance +-12/+-24 (acoustic); a repeat of the last correct note's name is ignored; wrong notes not judged before the
  first correct note; `continueAfterError = true`; `allowHarmonics` user setting, default off.
- Follow and Lead are one-hand only (also with MIDI).
- Grade 5 ABRSM tempos: scales 120, arpeggios/broken chords 88.

## Status
- Stage 0: DONE 28 Oct 2026 - runs as "SA Flutter" on Samsung, iPhone and Chrome; committed.
- Stage 1: DONE 29 Oct 2026 - sound and metronome OK on Samsung, Chrome and iPhone (release build); Yamaha default piano;
  new app icon; committed.

## Test log
- 28 Oct 2026, FL on Samsung (YIN), 2-octave C major, loudness filter 0.0: scale heard accurately.
  End Scale: quietest C5 peak 0.010 (first reading 0.010, 2 readings); loudest B5 peak 0.094 (first 0.050, 12 readings).
  => Android YIN filter must be below ~0.010 to catch the quietest notes. Still to measure: room noise with nothing playing.
- 28 Oct 2026: default loudness filter set to 0 for YIN on all platforms (Android, web, iOS); AudioKit on iOS keeps SA's 0.03.
  Listening screen defaults to 1 octave and shows the scale's first note beside Start/Stop while listening.
- 28 Oct 2026, web (Chrome on Mac, FL code), YIN, filter 0, 1-octave C major: completed 15/15, 0 wrong, but E4 missed twice
  (recovered by SA's 2-note lookahead). Repeated B5 readings: E4's 3rd harmonic (330 Hz x 3 = 989 Hz = B5) and B4's octave
  (494 x 2 = 988 Hz), plus C6 (C5's octave). All ignored only because they fall outside the scale range (> C5 + 3).
  Correct notes peaked at only 0.004-0.020 (quiet web input); noise lines 0.001-0.004 overlap, so the filter can't separate them.
  => Web YIN is picking harmonics; candidates: lower YIN threshold and/or prefer the longer period when d(2t)/d(3t) also dip.

- 28 Oct 2026: added an overtone check to all three YIN copies (Yin.kt, pitch.js, YinPitch.swift; also in FL): when the first
  dip scores above 0.05, a dip at 2x or 3x the delay scoring under 70% of it wins (the lower note). On synthetic piano tones
  (180 cases incl. noise and inharmonicity) it fixed all 36 E4->B5 errors and changed no correctly detected note.
  0.5 without the 0.05 gate wrongly lowered clean notes (E4->A2, B5->B4, C4->C3). Needs real-piano confirmation.
- 28 Oct 2026, FL on iPhone, AudioKit (SA), filter 0.03, 1-octave C major: completed 15/15, 0 wrong, no skipped notes
  (E4 heard both ways). Octave slips only (C6 for C5/C4, B5 for B4, F5 for F4), all ignored as outside the 1-octave range;
  in 2-3 octave scales SA's octave tolerance would forgive them. Correct notes peaked 0.082-0.179 (AudioKit scale);
  octave slips 0.032-0.106, so above SA's 0.03 filter. Benchmark for YIN comparisons.
- 28 Oct 2026, FL on iPhone, YIN (with overtone check), filter 0.004, 1-octave C major: completed 15/15, 0 wrong, no skipped
  notes; one octave slip (B5, ignored). Correct notes peaked 0.004-0.019, about 10x lower than AudioKit on the same iPhone
  (0.082-0.179): the two measure loudness differently (YIN: plain RMS of the block). David: YIN needs a lower loudness filter
  than AudioKit on all platforms. Quietest correct note (C5) only 0.004, so the 0.004 filter was right at the edge.
- 29 Oct 2026, SAF Stage 1 Sound screen, debug builds (`flutter run`), David:
  Load time: Chrome ~600 ms, Samsung ~1260 ms, iPhone ~4400 ms; switching Yamaha/Steinway works.
  Single notes: Chrome and Samsung clean; iPhone intermittent crackles at first, fine after a few plays.
  C major 2 octaves at 120 and 88, metronome + count-in: Chrome and Samsung even, legato, in time.
  Samsung: 35 ticks, average 3.7 ms late, worst 29.1 ms. iPhone: 24 ticks, average 4.7 ms, worst 71.3 ms on the first run,
  better on later runs (warm-up). Metronome only ~30 s: steady on Chrome and Samsung. Volume sliders fine.
  Chrome: sound starts only after Start sound, no delay or glitch. Not yet tested: iPhone silent switch, headphones (none).
  David prefers the Yamaha: made the default.
- 29 Oct 2026, iPhone release build (`flutter run --release`): fine (David) - the slow load, early crackles and first-run
  lateness were debug-build effects. Test iPhone sound/timing in release builds.
