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
12. **Landscape only** on phones and tablets, as SA (29 Oct 2026).
13. **Score** (29 Oct 2026): one-hand scales on one stave as SA; **hands-together scales on two staves** (RH treble, LH bass),
    unlike SA, which hides the score for them. **Fingering on the keyboard only, not on the staves** (as SA). No staccato
    marks (SA has none). Highlight: SA's green ring round the note while it sounds.

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
- **Stage 2 - Score via OSMD** (high risk; done 29 Oct 2026):
  - **Changed from the plan:** the MusicXML is built by `assets/score/score.js` (JavaScript shared by all three platforms),
    not in Dart: it can then be checked in a browser here against SA's screenshots. Dart has only the score description
    (`lib/score/score_spec.dart`, sent as JSON). Layout: drawn once on one line to measure it, then zoomed to fill the
    height, stretched across the width (or shrunk to the width if that runs out first); redrawn when its space changes size.
  - Web: only one score on screen at a time (score.js keeps one score); OSMD loads with window.define hidden (UMD bundle).
  - `lib/score/` (shared Dart): scale notes (MIDI, spelling step/alter/octave, length, hand) -> MusicXML with SA's rules
    (see "SA score layout" below); one or two staves; every note numbered for highlighting.
  - `assets/score/`: OSMD **2.2.1** pinned and bundled (BSD-3, 1.4 MB, works offline; fallback 1.9.9) + one HTML/JS bridge
    shared by all platforms: load score, highlight note n on/off, clear; reports render time and errors.
  - `lib/platform/score/`: one score widget; Android/iOS: `webview_flutter` page from assets (JS channel back to Dart);
    web: OSMD drawn straight into the page (HtmlElementView + JS interop). Start the web view once and keep it.
  - Highlight: JS draws SA's green ring as an SVG circle round the note head, toggled by note number - no re-render.
    Fallback: OSMD's note colouring.
  - Whole scale on one line, scaled to the width (as SA); lock the app to landscape (decision 12).
  - Score test screen (home > Score): choose a test scale, render time shown; Play at tempo with the Stage 1 player (Yamaha)
    and the ring following; highlight lateness (average/worst) like the Sound screen's timing line.
  - Test scales (typed-in note lists until Stage 3): C major RH 2 oct; Ab major LH (flats, mid-bar clef changes);
    F harmonic minor RH; F melodic minor RH and LH (naturals up, flats down); B dim 7th RH and LH; stress: F# major RH
    (6 sharps, E#), G# harmonic minor (F double sharp); one hands-together scale on two staves (e.g. A major).
  - Pass: matches SA's screenshots (`docs/sa_reference/`) on Samsung, iPhone, Chrome; render < ~0.5 s on Samsung;
    ring in time at 120; readable in landscape. Fallback: colour SVG directly, or draw the staff in Dart.
  - Estimate 2-3 sessions.
- **Stage 3 - Scale model, Grade 5** (done 30 Oct 2026; Samsung/iPhone run still due):
  - `lib/music/scale.dart`: SA's `Scale.swift` ported for **all** SA scale types (decision: port all, list and check Grade 5),
    kept as close to SA as possible including its quirks (e.g. the melodic-minor counter carries over between hands;
    getHighPointIndex reads the right hand). Notes, values, start notes, contrary motion, segments, **fingering** and
    finger-break colours (decision: fingering now; shown on the keyboard in Stage 4). Plain Dart.
  - `lib/music/abrsm_grade5.dart`: SA's 38 ABRSM Grade 5 exercises in SA's order; hands-together ones also practised
    with one hand (`Scale.withHands`, SA's Select Hands).
  - `lib/music/scale_spelling.dart`: SA's key signatures; spelling the musical way (a letter per scale step, chord-note
    letters for arpeggios); chromatic as SA (C-column spellings, the first accidental drawn decides sharps or flats for the
    whole score - so SA's F#/A# chromatic is written in flats).
  - SA reference: new SA test `ScalesAcademyTests/ExportForSAFTests.swift` (agreed; not app code) writes
    `test/sa_reference/abrsm_grade5.json` (run on an iOS Simulator). `dart run tools/check_scales.dart` compares note by note.
  - Score screen: SA's Grade 5 list with Together / LH / RH; the chromatic is shown on two staves (decision: try it).
  - score.js: a left-hand clef change at the very start (a high left hand, e.g. the chromatic) is the stave's first clef;
    tighter note spacing (OSMD VoiceSpacing 0.5 / 1.5, default 0.85 / 3) so the line fits across at a larger size (a line
    that doesn't fit is wrapped by OSMD, so the spacing decides the size).
  - Known SA difference kept: after a mid-bar clef change SA doesn't repeat an accidental cancelled earlier in the bar
    (chromatic LH: D after Db, SA draws no natural); SAF/OSMD draws the natural (correct notation) - David, 30 Oct 2026: keep SAF's natural.
- **Stage 4 - Keyboard and inputs**: Dart keyboard; microphone, MIDI and on-screen touch feeding one note stream.
- **Stage 5 - Follow and Lead**: port SA `ExerciseHandler`; compare with SA on iPhone at the piano; Samsung; MIDI; touch.
- **Stage 5b - Hands together with MIDI** (agreed with David 31 Oct 2026): Follow and Lead for hands-together exercises when
  listening to a MIDI keyboard - at each step expect both hands' notes within a short window; results per hand. (SA has
  one-hand Follow/Lead only.) Microphone: follow by note name only (it can't tell the hands apart: in similar motion the
  RH note is the LH note's 2nd harmonic); maybe later an experiment checking the two expected pitches for contrary motion.
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

## SA score layout (SA code + David's screenshots in docs/sa_reference/, 29 Oct 2026)
- One line for the whole scale, below the keyboard; no scrolling. SA hides the score for hands-together scales and
  chromatic scales over 1 octave (SAF shows two staves for hands together - decision 13).
- Clef, key signature and **4/4 time signature shown** (3/8 for broken chords); bar lines shown; final barline light-heavy.
- Scale notes are quavers beamed in groups of 4 (half bars); last bar: the final note as a crotchet, then rests to fill it
  (dim 7th: crotchet, crotchet rest, minim rest; 2-octave scales: 4 quavers, crotchet, crotchet rest).
- Accidentals per bar (bar lines count); e.g. F melodic minor: naturals on D and E going up, flats again in the same bar
  coming down (Eb after E natural). Dim 7th: no key signature, flat on every Ab.
- LH clef changes **at the start of a group of 4 quavers, also mid-bar** (Ab major LH: treble clef half way through bar 2,
  bass clef back half way through bar 3), when a group would need too many ledger lines (offset > 8 above in bass,
  < -7 below in treble; `ScalesModel.createScore`); can be turned off per scale (`clefSwitch: false`).
  SA draws mid-bar clefs full size; OSMD draws them smaller (normal engraving).
- Highlight: green ring (FigmaColors green) round the sounding note (Hear; Follow/Lead correct notes).

## SA functionality to carry over (survey of SA code, 29 Oct 2026; not complete)
- Start: Welcome; user set-up (name, board ABRSM, grade); several users ("Who wants to play?"); tabs Activities, Users,
  Subscriptions, Settings (+ Log tab in logging mode: a student named "debug").
- Activities: Choose Your Exercise (filter by type and key), Practice Chart (days of the week, Shuffle, harmonic/melodic
  choice), Spin the Wheel (random exercise, "exam conditions").
- Hands-together scale: Select Hands screen - Hands Together, Practise Left Hand, Practise Right Hand.
- Scale screen: title, help (?), grade and board; metronome bar with tempo slider and up/down arrows; keyboard(s) with
  fingering numbers (orange = finger after a thumb crossing/position change) and a hand icon at the start key; score;
  buttons Follow, Lead (one hand only), Play Along, Backing Track (scales with backing chords; SoundFont presets),
  Record (count-in at 90 shown on screen, silent metronome) and Hear Recording.
- Results: stars/badges per note during an exercise (animal badges), "Good job" message.
- Settings: keyboard colour, Listen with (microphone or USB/Bluetooth MIDI keyboard, Check), consecutive count gate,
  minimum volume, Allow Harmonics, debug mode, email feedback; piano calibration screen; subscriptions/licence; help texts.

## Status
- Stage 0: DONE 28 Oct 2026 - runs as "SA Flutter" on Samsung, iPhone and Chrome; committed.
- Stage 3: DONE 30 Oct 2026, committed (web run by David; Samsung and iPhone run still due). Checked against SA's export (98 exercises: 38 + RH/LH of 30 hands-together):
  `tools/check_scales.dart` all 98 match (4604 notes: MIDI, value, finger, finger breaks, segments; 3000 spellings; key
  signatures); OSMD's drawn accidentals match SA's in 97 - the chromatic's one natural above (kept, David).
- Stage 2: DONE 29 Oct 2026 - Score test screen (home > Score) OK on Chrome, Samsung and iPhone; landscape lock works; committed.
  To do later (Stage 7, real screens): start the score web view when the app starts and keep it, so the first score on
  Android/iOS doesn't wait ~1.2-1.8 s for the web view and OSMD to load.
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
- 29 Oct 2026, SAF Stage 2 Score screen (David; Chrome and Samsung debug, iPhone debug). Scores look like SA's (Ab major LH,
  F melodic minor RH, dim 7th RH); ring in time at 120 and 88; stays in landscape; nothing odd on first open.
  Chrome: drawn in 38 ms (C major), 13 ms (Ab major LH); ticks avg 0.6-1.0 ms late, worst 1.8 ms; highlight round trip
  avg 0.3-0.6 ms, worst 1.9 ms.
  Samsung: first draw 199 ms (OSMD) but 1174 ms from opening the screen (web view start + loading OSMD), then drawn again
  in 64 ms (the web view's size settled - redraw on resize); ticks avg 1.6-1.7 ms, worst 3.5 ms; round trip avg 13-15 ms,
  worst 32 ms (about one screen frame).
  iPhone (debug): drawn in 81 ms, 1804 ms from opening the screen; ticks avg 1.9 ms, worst 3.1 ms; round trip avg 4.6 ms,
  worst 16 ms.

- 30 Oct 2026, Stage 3 checks (Claude): SA test "Export for SAF" run by David on the iPhone 13 Simulator (it could not write
  to the DynabookSSD - macOS permission - so David copied it from the Simulator's tmp folder). check_scales: 98/98 match
  first time; a deliberately broken fingering was caught (4 exercises). Accidentals drawn by OSMD vs SA: 97/98 match.
  All 98 scores draw in Chromium, avg 17 ms.
- 30 Oct 2026, David: `flutter test` - 22 tests passed (3 s). Score screen run on the web (debug): Grade 5 list, Together/LH/RH, A major hands together drawn in 52 ms.

- 31 Oct 2026: David upgraded Flutter to 3.47.9 stable (c197ca5199; Dart 3.13.7 unchanged; no package changes).
  `flutter test` 22 passed; Claude: `dart analyze` no issues and check_scales 98/98 on the same Flutter.
- 31 Oct 2026, Stage 3 device runs (David, test log): Samsung (debug) and Chrome (debug). Scores look good compared with SA;
  chromatic very small but just readable; nothing odd on opening the Score screen; `flutter test` passed.
  Samsung: draws 43-118 ms after the first (283 ms first, 1626 ms from opening the screen); play ticks avg 1.5-1.7 ms late,
  worst 4.3 ms; ring round trip avg 14-17 ms, worst 32 ms. Chrome: draws 8-48 ms; ticks avg 0.6-0.8 ms, worst 2.0 ms;
  round trip avg 0.3-0.4 ms. Found and fixed: screen size 0x0 in the log header on Android; a score drawn twice when
  the number of staves changed (now drawn once; a redraw on resize is logged as "Redraw"). iPhone run still to do.
- 31 Oct 2026: app-wide test log (lib/log/test_log.dart): title-bar buttons Log to console (2 blank lines, START/END),
  Copy log (for email), Clear; each line prefixed with the test's settings; uncaught errors logged as [ERROR] with the
  start of the stack trace. Score screen: nothing below the staff.
