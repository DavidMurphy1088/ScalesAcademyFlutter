/// Which hand a stave is for
enum Hand { right, left }

/// One stave of a score: one hand's notes, in playing order
class ScoreStave {
  final Hand hand;

  /// Note names with their spelling: letter, accidental (# b x bb), octave - e.g. "Ab3", "E#5", "Fx4"
  final List<String> notes;

  /// Note lengths in crotchets; null = SA's default (quavers, the last note a crotchet)
  final List<double>? values;

  const ScoreStave({required this.hand, required this.notes, this.values});

  /// The MIDI numbers of [notes], for playing them
  List<int> get midis => notes.map(noteNameToMidi).toList();

  Map<String, dynamic> toJson() => {
        'hand': hand.name,
        'notes': notes.join(' '),
        if (values != null) 'values': values,
      };
}

/// A scale's score (made from SA's scale model by lib/score/scale_score.dart), drawn by assets/score/score.js with SA's layout rules (ScalesModel.createScore):
/// key signature, 4/4, bar lines, quavers beamed in fours, rests to fill the last bar, and the left hand's
/// clef changes. One stave for one hand; two (right hand first) for hands together.
class ScoreSpec {
  final String id;
  final String name;

  /// Crotchet beats per minute (SA's "♩ = 120")
  final int tempo;

  /// Key signature: sharps (+) or flats (-), e.g. -4 for A flat major / F minor
  final int keyFifths;
  final String keyMode;
  final List<int> time;

  /// SA's left-hand clef switching (some SA scales turn it off: ScaleCustomisation clefSwitch)
  final bool clefSwitch;
  final List<ScoreStave> staves;

  const ScoreSpec({
    required this.id,
    required this.name,
    required this.tempo,
    required this.keyFifths,
    this.keyMode = 'major',
    this.time = const [4, 4],
    this.clefSwitch = true,
    required this.staves,
  });

  ScoreStave? stave(Hand hand) {
    for (final s in staves) {
      if (s.hand == hand) return s;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'key': {'fifths': keyFifths, 'mode': keyMode},
        'time': time,
        'clefSwitch': clefSwitch,
        'staves': [for (final s in staves) s.toJson()],
      };

  factory ScoreSpec.fromJson(Map<String, dynamic> json) {
    final key = json['key'] as Map<String, dynamic>;
    return ScoreSpec(
      id: json['id'] as String,
      name: json['name'] as String,
      tempo: json['tempo'] as int,
      keyFifths: key['fifths'] as int,
      keyMode: (key['mode'] as String?) ?? 'major',
      time: json['time'] == null ? const [4, 4] : List<int>.from(json['time'] as List),
      clefSwitch: (json['clefSwitch'] as bool?) ?? true,
      staves: [
        for (final s in json['staves'] as List)
          ScoreStave(
            hand: (s['hand'] as String) == 'left' ? Hand.left : Hand.right,
            notes: (s['notes'] as String).trim().split(RegExp(r'\s+')),
            values: s['values'] == null ? null : [for (final v in s['values'] as List) (v as num).toDouble()],
          ),
      ],
    );
  }
}

const _pitchClass = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
const _alters = {'': 0, '#': 1, 'x': 2, '##': 2, 'b': -1, 'bb': -2};
final _noteName = RegExp(r'^([A-G])(##|#|x|bb|b|)(-?\d)$');

/// "Ab3" -> 56, "C4" -> 60, "E#5" -> 77, "Fx4" -> 67 (same as parseNote in score.js)
int noteNameToMidi(String name) {
  final m = _noteName.firstMatch(name.trim());
  if (m == null) throw FormatException('Bad note name: $name');
  final octave = int.parse(m.group(3)!);
  return (octave + 1) * 12 + _pitchClass[m.group(1)!]! + _alters[m.group(2)!]!;
}
