// SA Flutter score: builds MusicXML from a scale and draws it with OpenSheetMusicDisplay (OSMD),
// laid out as Scales Academy's score (ScalesModel.createScore). The same file is used on Android and iOS
// (inside a web view, score.html) and on the web (loaded into the page by lib/platform/score/score_view_web.dart).
//
// Dart -> JS:  SAFScore.load(specJson), SAFScore.highlight(hand, index, on, seq), SAFScore.clear()
// JS -> Dart:  messages (JSON strings) through the function given to SAFScore.init:
//   {type:'ready'} {type:'rendered', ms, notes:{right:n, left:n}, redraw} {type:'error', message}
//   (redraw: true when the score was drawn again because its space changed size, not because Dart asked)
//   {type:'highlighted', seq}   (reply to a highlight that carried a seq number, to time the round trip)
//
// Spec (JSON):
//   { key: {fifths: -4, mode: 'minor'}, time: [4, 4], clefSwitch: true,
//     staves: [ {hand: 'right'|'left', notes: 'F3 G3 Ab3 ...', values: [0.5, ...] (optional)} ] }
//   Notes: letter, accidental (# b x bb), octave. Values in crotchets; default: quavers, the last note a crotchet (SA).
//   Two staves: right hand first. Both staves must have the same note values (SA plays them together).
(function () {
  'use strict';

  const RING_COLOR = '#9CD762'; // SA FigmaColors green, shade 0
  const DIVISIONS = 12; // per crotchet: quaver 6, triplet quaver 4
  const STEPS = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  const PITCH_CLASS = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
  const ALTERS = { '': 0, '#': 1, 'x': 2, '##': 2, 'b': -1, 'bb': -2 };

  // ---------------------------------------------------------------- notes

  /** "Ab3" -> {step:'A', alter:-1, octave:3, midi:56, position:diatonic steps from C0} */
  function parseNote(name) {
    const m = /^([A-G])(##|#|x|bb|b|)(-?\d)$/.exec(name.trim());
    if (!m) throw new Error('Bad note name: ' + name);
    const step = m[1];
    const alter = ALTERS[m[2]];
    const octave = parseInt(m[3], 10);
    return {
      step, alter, octave,
      midi: (octave + 1) * 12 + PITCH_CLASS[step] + alter,
      position: octave * 7 + STEPS.indexOf(step),
    };
  }

  // Middle line of the stave, in diatonic steps from C0: treble B4, bass D3
  const MIDDLE_LINE = { treble: 4 * 7 + 6, bass: 3 * 7 + 1 };

  /** SA StaffClef offsetFromStaffMidline: steps above (+) or below (-) the stave's middle line */
  function offsetFromMiddle(note, clef) {
    return note.position - MIDDLE_LINE[clef];
  }

  // ---------------------------------------------------------------- layout (SA rules)

  /**
   * Time slices as SA builds them: one per scale note (both hands together), then rests to fill the last bar.
   * Each slice: {start (crotchets from the start), value, notes: {right: note|null, left: note|null}, rest: bool}
   */
  function buildSlices(spec) {
    const staves = spec.staves;
    const parsed = staves.map((s) => s.notes.trim().split(/\s+/).map(parseNote));
    const count = parsed[0].length;
    for (const p of parsed) {
      if (p.length !== count) throw new Error('Both hands must have the same number of notes');
    }
    const values = staves[0].values || parsed[0].map((_, i) => (i === count - 1 ? 1.0 : 0.5));
    const [top, bottom] = spec.time || [4, 4];
    if (bottom !== 4) throw new Error('Only x/4 time is supported so far'); // SA broken chords (3/8) come later
    const barValue = top;

    const slices = [];
    let start = 0;
    for (let i = 0; i < count; i++) {
      const notes = {};
      staves.forEach((s, k) => { notes[s.hand] = parsed[k][i]; });
      slices.push({ start, value: values[i], notes, rest: false, index: i });
      start += values[i];
    }
    // SA addFinalRests (4/4): rests to fill the last bar
    const used = start % barValue;
    const restValues = { 1: [1.0, 2.0], 2: [2.0], 3: [1.0] }[used] || [];
    for (const v of restValues) {
      slices.push({ start, value: v, notes: {}, rest: true });
      start += v;
    }
    return { slices, barValue, total: start };
  }

  /**
   * SA's left-hand clef switching (ScalesModel.createScore): at the start of each group of 2 crotchets
   * (4 quavers), look at the left-hand notes of the group before. If one of them is more than 8 steps above
   * the middle line in the bass clef, or more than 7 below it in the treble clef, change clef at the start
   * of that group. Rest slices count as group starts too; the final group is not checked (as SA).
   * Returns [{start, clef}] for the left hand, and its first clef ('bass').
   */
  function leftHandClefChanges(slices, enabled) {
    const changes = [];
    if (!enabled) return changes;
    const groupValue = 2.0;
    let clef = 'bass';
    let groupStart = 0;
    let offsets = [];
    for (const slice of slices) {
      const inGroup = slice.start % groupValue;
      if (Math.abs(inGroup) < 1e-6 || Math.abs(inGroup - groupValue) < 1e-6) {
        if (offsets.length > 0) {
          const highest = Math.max(...offsets);
          const lowest = Math.min(...offsets);
          if ((highest > 8 && clef === 'bass') || (lowest < -7 && clef === 'treble')) {
            clef = clef === 'bass' ? 'treble' : 'bass';
            changes.push({ start: groupStart, clef });
          }
        }
        offsets = [];
        groupStart = slice.start;
      }
      const note = slice.notes.left;
      if (note) offsets.push(offsetFromMiddle(note, clef));
    }
    return changes;
  }

  // ---------------------------------------------------------------- MusicXML

  const TYPES = [[4, 'whole', false], [3, 'half', true], [2, 'half', false], [1.5, 'quarter', true],
    [1, 'quarter', false], [0.75, 'eighth', true], [0.5, 'eighth', false], [0.25, '16th', false]];

  function typeOf(value) {
    for (const [v, type, dot] of TYPES) {
      if (Math.abs(v - value) < 1e-6) return { type, dot };
    }
    throw new Error('Unsupported note value ' + value);
  }

  function clefXml(clef, number) {
    const [sign, line] = clef === 'treble' ? ['G', 2] : ['F', 4];
    return `<clef number="${number}"><sign>${sign}</sign><line>${line}</line></clef>`;
  }

  function buildMusicXml(spec) {
    const { slices, barValue, total } = buildSlices(spec);
    const hands = spec.staves.map((s) => s.hand); // staff 1, staff 2
    const twoStaves = hands.length === 2;
    const leftStaff = hands.indexOf('left') + 1; // 0 if no left hand
    const clefChanges = leftStaff ? leftHandClefChanges(slices, spec.clefSwitch !== false) : [];
    // A change at the very start (e.g. a left hand starting high, as the chromatic's) is the stave's first clef
    let leftFirstClef = 'bass';
    if (clefChanges.length > 0 && clefChanges[0].start < 1e-6) {
      leftFirstClef = clefChanges.shift().clef;
    }
    const [top, bottom] = spec.time || [4, 4];
    const bars = Math.ceil(total / barValue - 1e-6);

    let xml = '<?xml version="1.0" encoding="UTF-8"?>' +
      '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">' +
      '<score-partwise version="4.0"><part-list><score-part id="P1"><part-name print-object="no">Piano</part-name></score-part></part-list><part id="P1">';

    for (let bar = 0; bar < bars; bar++) {
      const barStart = bar * barValue;
      const barEnd = barStart + barValue;
      xml += `<measure number="${bar + 1}">`;
      if (bar === 0) {
        xml += `<attributes><divisions>${DIVISIONS}</divisions>` +
          `<key><fifths>${spec.key.fifths}</fifths><mode>${spec.key.mode || 'major'}</mode></key>` +
          `<time><beats>${top}</beats><beat-type>${bottom}</beat-type></time>` +
          (twoStaves ? '<staves>2</staves>' : '') +
          hands.map((h, k) => clefXml(h === 'right' ? 'treble' : leftFirstClef, k + 1)).join('') +
          '</attributes>';
      }
      hands.forEach((hand, k) => {
        const staff = k + 1;
        if (k > 0) xml += `<backup><duration>${Math.round(barValue * DIVISIONS)}</duration></backup>`;
        const inBar = slices.filter((s) => s.start >= barStart - 1e-6 && s.start < barEnd - 1e-6);
        // Beams: quavers in groups of 2 crotchets (SA)
        const beamGroups = {};
        for (const s of inBar) {
          if (s.rest || Math.abs(s.value - 0.5) > 1e-6) continue;
          const g = Math.floor((s.start + 1e-6) / 2.0);
          (beamGroups[g] = beamGroups[g] || []).push(s);
        }
        for (const s of inBar) {
          if (staff === leftStaff) {
            const change = clefChanges.find((c) => Math.abs(c.start - s.start) < 1e-6);
            if (change) xml += `<attributes>${clefXml(change.clef, twoStaves ? staff : 1)}</attributes>`;
          }
          const { type, dot } = typeOf(s.value);
          const duration = Math.round(s.value * DIVISIONS);
          const staffXml = twoStaves ? `<staff>${staff}</staff>` : '';
          if (s.rest) {
            xml += `<note><rest/><duration>${duration}</duration><voice>${staff}</voice><type>${type}</type>${dot ? '<dot/>' : ''}${staffXml}</note>`;
            continue;
          }
          const n = s.notes[hand];
          let beam = '';
          const group = beamGroups[Math.floor((s.start + 1e-6) / 2.0)];
          if (group && group.length > 1 && group.includes(s)) {
            const pos = group.indexOf(s);
            beam = `<beam number="1">${pos === 0 ? 'begin' : pos === group.length - 1 ? 'end' : 'continue'}</beam>`;
          }
          xml += '<note><pitch>' +
            `<step>${n.step}</step>${n.alter ? `<alter>${n.alter}</alter>` : ''}<octave>${n.octave}</octave></pitch>` +
            `<duration>${duration}</duration><voice>${staff}</voice><type>${type}</type>${dot ? '<dot/>' : ''}` +
            `${staffXml}${beam}</note>`;
        }
      });
      if (bar === bars - 1) xml += '<barline location="right"><bar-style>light-heavy</bar-style></barline>';
      xml += '</measure>';
    }
    xml += '</part></score-partwise>';
    return xml;
  }

  // ---------------------------------------------------------------- drawing and highlighting

  let container = null;
  let send = (message) => console.log('SAFScore', message);
  let osmd = null;
  let svg = null;
  let noteTargets = { right: [], left: [] }; // graphical notes in scale order, per hand
  let rings = { right: [], left: [] };
  let handOfStaff = [];

  function post(obj) {
    try { send(JSON.stringify(obj)); } catch (e) { console.log('SAFScore post failed', e); }
  }

  let lastSpec = null; // drawn again when the space for the score changes size (e.g. turning the device)
  let pendingSpec = null; // asked for before the score had any size (web view not laid out yet)
  let lastSize = '';
  let resizeTimer = null;

  function init(element, sendMessage) {
    container = element;
    if (sendMessage) send = sendMessage;
    if (typeof opensheetmusicdisplay === 'undefined') {
      post({ type: 'error', message: 'OSMD did not load' });
      return;
    }
    if (typeof ResizeObserver !== 'undefined') {
      new ResizeObserver(onResize).observe(container);
    } else {
      window.addEventListener('resize', onResize);
    }
    post({ type: 'ready' });
  }

  function hasSize() {
    return container.clientWidth > 0 && container.clientHeight > 0;
  }

  function onResize() {
    if (!hasSize()) return;
    const size = container.clientWidth + 'x' + container.clientHeight;
    if (size === lastSize) return;
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      // A score waiting for a size is a first drawing; otherwise it is the last score drawn again
      const redraw = !pendingSpec;
      const spec = pendingSpec || lastSpec;
      pendingSpec = null;
      if (spec) draw(spec, redraw);
    }, 100);
  }

  /** Draws the score Dart asks for */
  function load(specJson) {
    return draw(specJson, false);
  }

  async function draw(specJson, redraw) {
    const t0 = performance.now();
    try {
      const spec = typeof specJson === 'string' ? JSON.parse(specJson) : specJson;
      if (!hasSize()) {
        pendingSpec = spec; // drawn by onResize once the score has a size
        return;
      }
      lastSpec = spec;
      lastSize = container.clientWidth + 'x' + container.clientHeight;
      const xml = buildMusicXml(spec);
      handOfStaff = spec.staves.map((s) => s.hand);
      container.innerHTML = '';
      const bars = (xml.match(/<measure /g) || []).length;
      osmd = new opensheetmusicdisplay.OpenSheetMusicDisplay(container, {
        backend: 'svg',
        autoResize: false,
        autoBeam: false,
        drawTitle: false,
        drawSubtitle: false,
        drawComposer: false,
        drawLyricist: false,
        drawCredits: false,
        drawPartNames: false,
        drawPartAbbreviations: false,
        drawMeasureNumbers: false,
        drawMetronomeMarks: false,
        disableCursor: true,
      });
      await osmd.load(xml);
      layOutOnOneLine(bars);
      fitToWidth();
      collectNotes();
      post({ type: 'rendered', ms: Math.round(performance.now() - t0), redraw,
        notes: { right: noteTargets.right.length, left: noteTargets.left.length } });
    } catch (e) {
      post({ type: 'error', message: String(e && e.message ? e.message : e) });
    }
  }

  function setRules(singleLine, bars) {
    const rules = osmd.EngravingRules;
    rules.RenderSingleHorizontalStaffline = singleLine;
    // Tighter than OSMD's default note spacing (0.85, 3), closer to SA's: the whole scale fits across at a larger size.
    // (A line that doesn't fit across is wrapped by OSMD, so the spacing - not the zoom - decides the size.)
    rules.VoiceSpacingMultiplierVexflow = 0.5;
    rules.VoiceSpacingAddendVexflow = 1.5;
    rules.RenderXMeasuresPerLineAkaSystem = singleLine ? 0 : bars;
    rules.StretchLastSystemLine = !singleLine;
    rules.PageTopMargin = 0.5;
    rules.PageTopMarginNarrow = 0.5;
    rules.PageBottomMargin = 0.5;
    rules.PageLeftMargin = handOfStaff.length > 1 ? 2.0 : 0.5; // room for the brace of two staves
    rules.PageRightMargin = 0.5;
  }

  function drawnSize() {
    const s = container.querySelector('svg');
    return { w: parseFloat(s.getAttribute('width')), h: parseFloat(s.getAttribute('height')) };
  }

  /**
   * As SA: the whole scale on one line across the full width.
   * 1. Draw it on one line at its natural spacing (zoom 1) to measure its width and height.
   * 2. The zoom that fills the height (zH) and the one that fills the width (zW):
   *    zH <= zW: there is room to spare across - draw at zH as one system stretched to the full width (notes spread out);
   *    otherwise the width runs out first - draw the single line at zW (shorter than the space available).
   */
  function layOutOnOneLine(bars) {
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;
    setRules(true, bars);
    osmd.Zoom = 1.0;
    osmd.render();
    const natural = drawnSize();
    const zH = height / natural.h;
    const zW = width / natural.w;
    if (zH <= zW) {
      setRules(false, bars);
      osmd.Zoom = zH;
    } else {
      osmd.Zoom = zW;
    }
    osmd.render();
    // The single line was drawn with more space above and below than the stretched line, so zH comes out too small:
    // measure the stretched line's height and zoom up to fill the height - but never past zW, beyond which the notes
    // would need more room across than their natural spacing
    if (zH <= zW) {
      for (let i = 0; i < 3; i++) {
        const drawn = drawnSize();
        if (!(drawn.h > 0)) break;
        const next = Math.min(zW, osmd.Zoom * (height / drawn.h));
        if (Math.abs(next - osmd.Zoom) < 0.01) break;
        osmd.Zoom = next;
        osmd.render();
      }
    }
  }

  /** Scale the drawn SVG to fill the container's width (or height, if that runs out first), left aligned */
  function fitToWidth() {
    svg = container.querySelector('svg');
    if (!svg) throw new Error('No SVG drawn');
    // Keep OSMD's own viewBox (it is in unzoomed units); only let the browser scale it into the space available
    if (!svg.getAttribute('viewBox')) {
      svg.setAttribute('viewBox', `0 0 ${parseFloat(svg.getAttribute('width'))} ${parseFloat(svg.getAttribute('height'))}`);
    }
    svg.setAttribute('preserveAspectRatio', 'xMinYMid meet');
    const page = svg.parentElement; // OSMD's page div
    if (page && page !== container) {
      page.style.width = '100%';
      page.style.height = '100%';
    }
    svg.removeAttribute('width');
    svg.removeAttribute('height');
    svg.style.width = '100%';
    svg.style.height = '100%';
    svg.style.display = 'block';
  }

  /** The drawn notes of each hand, in playing order (rests left out) */
  function collectNotes() {
    noteTargets = { right: [], left: [] };
    rings = { right: [], left: [] }; // the old rings went with the old SVG
    const measures = osmd.GraphicSheet.MeasureList; // [measure][staff]
    for (let staff = 0; staff < handOfStaff.length; staff++) {
      const hand = handOfStaff[staff];
      for (const measureStaves of measures) {
        const measure = measureStaves[staff];
        if (!measure) continue;
        for (const entry of measure.staffEntries) {
          for (const voiceEntry of entry.graphicalVoiceEntries) {
            for (const note of voiceEntry.notes) {
              if (note.sourceNote.isRest()) continue;
              noteTargets[hand].push(note);
            }
          }
        }
      }
    }
  }

  /** SA's green ring round the note head (TimeSliceView NoteHiliteView: diameter 1.7 note widths, line 3) */
  function makeRing(note) {
    const heads = note.getNoteheadSVGs ? note.getNoteheadSVGs() : [];
    const head = heads && heads.length ? heads[0] : note.getSVGGElement();
    const box = head.getBBox();
    const r = Math.max(box.width, box.height) * 0.95;
    const ring = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    ring.setAttribute('cx', box.x + box.width / 2);
    ring.setAttribute('cy', box.y + box.height / 2);
    ring.setAttribute('r', r);
    ring.setAttribute('fill', 'none');
    ring.setAttribute('stroke', RING_COLOR);
    ring.setAttribute('stroke-width', Math.max(1.5, r * 0.28));
    ring.style.display = 'none';
    svg.appendChild(ring);
    return ring;
  }

  function highlight(hand, index, on, seq) {
    const notes = noteTargets[hand] || [];
    if (index >= 0 && index < notes.length) {
      let ring = rings[hand][index];
      if (!ring) ring = rings[hand][index] = makeRing(notes[index]);
      ring.style.display = on ? '' : 'none';
    }
    if (seq !== undefined && seq !== null) post({ type: 'highlighted', seq });
  }

  function clear() {
    for (const hand of ['right', 'left']) {
      for (const ring of rings[hand]) if (ring) ring.style.display = 'none';
    }
  }

  /**
   * For checking against SA (Stage 3): the accidental drawn on each note of each hand, in playing order -
   * null (none), 0 (natural), 1 (sharp), -1 (flat), 2 (double sharp), -2 (double flat), as SA's NoteStaffPlacement.accidental
   */
  function drawnAccidentals() {
    const codes = { '#': 1, 'b': -1, 'n': 0, '##': 2, 'bb': -2 };
    const result = {};
    for (const hand of ['right', 'left']) {
      result[hand] = noteTargets[hand].map((note) => {
        const staveNote = note.vfnote && note.vfnote[0];
        const modifiers = staveNote && staveNote.getModifiers ? staveNote.getModifiers() : [];
        const accidental = modifiers.find((m) => m.getCategory && ['accidentals', 'Accidental'].includes(m.getCategory()));
        return accidental ? (codes[accidental.type] ?? accidental.type) : null;
      });
    }
    return result;
  }

  window.SAFScore = { init, load, highlight, clear, buildMusicXml, parseNote, leftHandClefChanges, buildSlices, drawnAccidentals };
})();
