// Compares SAF's scale model with Scales Academy's, note by note (Stage 3, 30 Oct 2026).
//
//   dart run tools/check_scales.dart            compare with test/sa_reference/abrsm_grade5.json
//   dart run tools/check_scales.dart --verbose  also list every exercise that matches
//
// The reference file is written by SA's test "Export for SAF" (ScalesAcademyTests/ExportForSAFTests.swift), run on an
// iOS Simulator. For each exercise (SA's Grade 5 list plus the RH/LH practice versions of the hands-together ones) it
// compares, for both hands: MIDI, note value, finger, finger-break colours (up/down) and segments; and from SA's score:
// the key signature and each shown note's spelling (letter, sharp/flat, octave).
// Plain Dart: runs without Flutter.

import 'dart:convert';
import 'dart:io';

import 'package:scales_academy_flutter/music/abrsm_grade5.dart';
import 'package:scales_academy_flutter/music/scale.dart';
import 'package:scales_academy_flutter/music/scale_spelling.dart';

void main(List<String> args) {
  final verbose = args.contains('--verbose');
  final file = File('test/sa_reference/abrsm_grade5.json');
  if (!file.existsSync()) {
    stderr.writeln('Not found: ${file.path}. Run SA\'s test "Export for SAF" on an iOS Simulator first.');
    exit(2);
  }
  final reference = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final exercises = (reference['exercises'] as List).cast<Map<String, dynamic>>();

  // SAF's exercises: the list, plus RH and LH practice versions of the hands-together ones (as SA's export)
  final saf = <String, Scale>{};
  final safOrder = <String>[];
  for (final listed in abrsmGrade5()) {
    final variants = [listed, if (listed.isHandsTogether) ...[listed.withHands([0]), listed.withHands([1])]];
    for (final s in variants) {
      saf[s.identificationKey] = s;
      safOrder.add(s.identificationKey);
    }
  }

  var matched = 0;
  var failed = 0;
  final problems = <String>[];
  final saKeys = <String>[];
  for (final ex in exercises) {
    final key = ex['key'] as String;
    saKeys.add(key);
    final scale = saf[key];
    if (scale == null) {
      problems.add('$key: in SA but not in SAF');
      failed++;
      continue;
    }
    final errors = compare(scale, ex);
    if (errors.isEmpty) {
      matched++;
      if (verbose) stdout.writeln('OK   $key');
    } else {
      failed++;
      problems.add('$key:\n    ${errors.take(12).join('\n    ')}${errors.length > 12 ? '\n    ... ${errors.length - 12} more' : ''}');
    }
  }
  for (final key in safOrder) {
    if (!saKeys.contains(key)) {
      problems.add('$key: in SAF but not in SA');
      failed++;
    }
  }
  if (saKeys.length == safOrder.length) {
    for (var i = 0; i < saKeys.length; i++) {
      if (saKeys[i] != safOrder[i]) {
        problems.add('Order differs at $i: SA ${saKeys[i]}, SAF ${safOrder[i]}');
        failed++;
        break;
      }
    }
  }

  for (final p in problems) {
    stdout.writeln('FAIL $p');
  }
  stdout.writeln('${reference['board']} grade ${reference['grade']} (SA export ${reference['generated']}): '
      '$matched exercises match, $failed problems');
  exit(failed == 0 ? 0 : 1);
}

List<String> compare(Scale scale, Map<String, dynamic> ex) {
  final errors = <String>[];
  void check(String what, Object? saf, Object? sa) {
    if ('$saf' != '$sa') errors.add('$what: SAF $saf, SA $sa');
  }

  check('name', scale.scaleName, nameWithoutHands(ex));
  check('tempo', scale.minTempo, ex['tempo']);
  check('hands', scale.hands, ex['hands']);
  check('time', [scale.timeSignature.top, scale.timeSignature.bottom], ex['time']);
  check('articulations', scale.articulationTypes.map((a) => a.description).toList(), ex['articulations']);

  // The scale model, both hands
  final notes = ex['notes'] as Map<String, dynamic>;
  for (final (hand, handName) in [(0, 'right'), (1, 'left')]) {
    final sa = (notes[handName] as List).cast<Map<String, dynamic>>();
    final mine = scale.notesOf(hand);
    if (sa.length != mine.length) {
      errors.add('$handName hand: SAF ${mine.length} notes, SA ${sa.length}');
      continue;
    }
    for (var i = 0; i < sa.length; i++) {
      final s = sa[i];
      final m = mine[i];
      final at = '$handName[$i]';
      check('$at midi', m.midi, s['midi']);
      check('$at value', m.value, (s['value'] as num).toDouble());
      check('$at sequence', m.sequence, s['sequence']);
      check('$at finger', m.finger, s['finger']);
      check('$at up', m.keyboardFingerColourTypeUp.name, s['up']);
      check('$at down', m.keyboardFingerColourTypeDown.name, s['down']);
      check('$at segments', m.segments, s['segments']);
    }
  }

  // The score: key signature and the shown notes' spellings
  final score = ex['score'] as Map<String, dynamic>;
  final key = keySignatureFor(scale);
  check('key signature', '${key.count} ${key.flats ? 'flat' : 'sharp'}', '${score['keyCount']} ${score['keyAccidental']}');
  final spelling = spellScale(scale);
  for (final staff in (score['staves'] as List).cast<Map<String, dynamic>>()) {
    final handName = staff['hand'] as String;
    final hand = handName == 'right' ? 0 : 1;
    final staffNotes = (staff['notes'] as List).cast<Map<String, dynamic>>();
    final mine = spelling[hand];
    if (staffNotes.length != mine.length) {
      errors.add('$handName staff: SAF ${mine.length} notes, SA ${staffNotes.length}');
      continue;
    }
    for (var i = 0; i < staffNotes.length; i++) {
      final s = staffNotes[i];
      final saSpelling = NoteSpelling(s['step'] as String, s['alter'] as int, s['octave'] as int);
      check('$handName staff[$i] (MIDI ${s['midi']}) spelling', mine[i].name, saSpelling.name);
    }
  }
  return errors;
}

/// SA's getScaleName(showHands: true, handFull: true) has the hand at the end; SAF compares the custom name or
/// "root type" - so compare with SA's name without the hand words
String nameWithoutHands(Map<String, dynamic> ex) {
  final custom = (ex['customisation'] as Map<String, dynamic>?)?['customScaleName'] as String?;
  if (custom != null && custom.isNotEmpty) return custom;
  var name = ex['name'] as String;
  for (final suffix in [' hands together', ' Right Hand', ' Left Hand', ' Contrary Motion']) {
    if (name.endsWith(suffix)) name = name.substring(0, name.length - suffix.length);
  }
  return name;
}
