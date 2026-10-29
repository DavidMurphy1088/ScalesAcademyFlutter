"""Render piano notes from a SoundFont to one audio file per MIDI note, for SA Flutter.
Usage: python3 render_piano.py <soundfont.sf2> <preset> <out_dir> [velocity] [format]
Each note: key down for HOLD seconds, then released, with RELEASE seconds of release tail.
SA Flutter used: Steinway_D.sf2 preset 0 velocity 64 gain 0 -> assets/sounds/piano_steinway;
 Yamaha-Grand-Lite-SF-v1.1.sf2 preset 0 velocity 64 gain 12 -> assets/sounds/piano_yamaha.
Needs: pip install soundfile numpy; pip install --no-deps tinysoundfont"""
import sys, os, numpy as np, soundfile as sf, tinysoundfont as tsf
SR=44100; HOLD=2.0; RELEASE=0.5   # 2.5 s per note; mono (the app holds every note in memory uncompressed)
sfpath, preset, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
vel = int(sys.argv[4]) if len(sys.argv) > 4 else 64
fmt = sys.argv[5] if len(sys.argv) > 5 else "ogg"
os.makedirs(out, exist_ok=True)
synth = tsf.Synth(samplerate=SR)
gain = float(sys.argv[6]) if len(sys.argv) > 6 else 0.0
sid = synth.sfload(sfpath, gain=gain)
print("preset:", synth.sfpreset_name(sid, 0, preset))
synth.program_select(0, sid, 0, preset)
peaks=[]; total=0
for midi in range(21, 109):
    synth.notes_off(); synth.sounds_off()
    synth.generate(int(SR*0.2))                  # flush
    synth.noteon(0, midi, vel)
    a = np.frombuffer(synth.generate(int(SR*HOLD)), dtype=np.float32).reshape(-1, 2).copy()
    synth.noteoff(0, midi)
    b = np.frombuffer(synth.generate(int(SR*RELEASE)), dtype=np.float32).reshape(-1, 2).copy()
    x = np.concatenate([a, b]).mean(axis=1, keepdims=True)   # mono
    # trim leading silence (keeps the attack instant) and fade the very end
    nz = np.where(np.abs(x).max(axis=1) > 1e-4)[0]
    if len(nz): x = x[nz[0]:]
    n = int(SR*0.02); x[-n:] *= np.linspace(1, 0, n)[:, None]
    peaks.append(float(np.abs(x).max()))
    path = os.path.join(out, f"{midi}.{fmt}")
    if fmt == "ogg": sf.write(path, x, SR, format="OGG", subtype="VORBIS")
    else: sf.write(path, x, SR, subtype="PCM_16")
    total += os.path.getsize(path)
print(f"88 notes, total {total/1e6:.1f} MB, peak min {min(peaks):.2f} max {max(peaks):.2f}")
