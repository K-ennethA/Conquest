extends SceneTree

## Headless generator for Conquest's DEFAULT placeholder audio.
##
## Procedurally synthesizes a small bank of SFX + one looping music bed as raw
## 16-bit mono PCM (22050 Hz), wraps each in an [AudioStreamWAV], and writes it
## to disk via [method AudioStreamWAV.save_to_wav]. It then rewrites
## res://game/audio/default_audio_library.tres so every slot references its
## generated .wav -- giving the project audio "out of the box" that a designer
## can later swap by dropping new files into the same slots.
##
## Run headless:
##   godot --headless -s dev_scripts/generate_default_audio.gd
##
## Design notes:
## * Fully DETERMINISTIC -- any noise uses a fixed-seed RandomNumberGenerator,
##   so re-running produces byte-identical output.
## * Amplitudes stay modest (~0.3-0.5 peak) and every clip gets short fades to
##   avoid clicks. Values are clamped to [-1, 1] on the way to 16-bit.
## * The music bed is composed on a strict bar grid with per-note fades, so the
##   last sample lands at a note boundary (near silence) exactly like the first
##   sample -- LOOP_FORWARD from loop_end back to 0 is therefore seamless.
##
## Nothing here edits AudioManager / AudioLibrary code; it only emits data
## (.wav files) and the data-only .tres that points at them.

const SR: int = 22050                 # sample rate (Hz)
const SFX_DIR: String = "res://game/audio/sfx"
const MUSIC_DIR: String = "res://game/audio/music"
const LIBRARY_PATH: String = "res://game/audio/default_audio_library.tres"
const SCRIPT_PATH: String = "res://game/audio/AudioLibrary.gd"

# Global click-safety fade applied to every NON-looping clip (samples).
const SAFETY_FADE: int = 96

var _rng := RandomNumberGenerator.new()
# slot name -> emitted res:// path (drives the .tres rewrite + summary).
var _emitted: Dictionary = {}


func _initialize() -> void:
	print("=== Conquest Default Audio Generator ===")
	_rng.seed = 0x00C0FFEE  # fixed seed -> deterministic noise

	_ensure_dir(SFX_DIR)
	_ensure_dir(MUSIC_DIR)

	# --- SFX -------------------------------------------------------------
	_emit("sfx_select",     SFX_DIR + "/select.wav",     _make_select())
	_emit("sfx_move",       SFX_DIR + "/move.wav",       _make_move())
	_emit("sfx_attack",     SFX_DIR + "/attack.wav",     _make_attack())
	_emit("sfx_hit",        SFX_DIR + "/hit.wav",        _make_hit())
	_emit("sfx_heal",       SFX_DIR + "/heal.wav",       _make_heal())
	_emit("sfx_death",      SFX_DIR + "/death.wav",      _make_death())
	_emit("sfx_turn_start", SFX_DIR + "/turn_start.wav", _make_turn_start())
	_emit("sfx_victory",    SFX_DIR + "/victory.wav",    _make_victory())
	_emit("sfx_defeat",     SFX_DIR + "/defeat.wav",     _make_defeat())
	_emit("sfx_ui_click",   SFX_DIR + "/ui_click.wav",   _make_ui_click())

	# --- Music (looping) -------------------------------------------------
	_emit("music_battle", MUSIC_DIR + "/battle_theme.wav", _make_music(), true)

	# --- Wire up the library --------------------------------------------
	var ok := _write_library()

	print("\n--- Summary ---")
	for slot in _emitted.keys():
		print("  %-14s -> %s" % [slot, _emitted[slot]])
	if ok:
		print("Library written: %s" % LIBRARY_PATH)
		print("DONE: %d clip(s) emitted." % _emitted.size())
		quit(0)
	else:
		printerr("FAILED to write library .tres")
		quit(1)


# =====================================================================
#  Emit / IO
# =====================================================================

func _ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		var err := DirAccess.make_dir_recursive_absolute(path)
		if err != OK:
			push_warning("Could not create dir %s (err %d)" % [path, err])


## Convert a float sample buffer to a 16-bit LE PCM AudioStreamWAV and save it.
func _emit(slot: String, path: String, buf: PackedFloat32Array, loop: bool = false) -> void:
	if not loop:
		_fade(buf, SAFETY_FADE, SAFETY_FADE)  # click safety on one-shots only

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = _to_bytes(buf)
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = buf.size()

	var err := wav.save_to_wav(path)
	if err != OK:
		printerr("  save failed: %s (err %d)" % [path, err])
		return
	_emitted[slot] = path
	print("  emitted %-24s %6d samples (%.2fs)%s"
		% [path.get_file(), buf.size(), float(buf.size()) / SR, "  [loop]" if loop else ""])


func _to_bytes(buf: PackedFloat32Array) -> PackedByteArray:
	var n := buf.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var s := clampf(buf[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(round(s * 32767.0)))
	return bytes


## Rewrite default_audio_library.tres so every slot references its .wav.
## Method (b): hand-written .tres text (proper Godot format). Chosen over
## load()+ResourceSaver because a just-saved raw .wav has no .import yet and
## cannot be load()ed within this same headless run.
func _write_library() -> bool:
	# Fixed ext_resource ids per slot (order matches the resource block).
	var slots := [
		"sfx_select", "sfx_move", "sfx_attack", "sfx_hit", "sfx_heal",
		"sfx_death", "sfx_turn_start", "sfx_victory", "sfx_defeat",
		"sfx_ui_click", "music_battle",
	]
	var ids: Dictionary = {}
	var lines := PackedStringArray()
	var load_steps := slots.size() + 2  # 11 slot ext + 1 script ext + 1 resource

	lines.append("[gd_resource type=\"Resource\" script_class=\"AudioLibrary\" load_steps=%d format=3]" % load_steps)
	lines.append("")
	lines.append("[ext_resource type=\"Script\" path=\"%s\" id=\"1_audiolib\"]" % SCRIPT_PATH)

	var idx := 2
	for slot in slots:
		if not _emitted.has(slot):
			push_warning("slot %s was not emitted; leaving null" % slot)
			continue
		var id := "%d_%s" % [idx, slot]
		ids[slot] = id
		lines.append("[ext_resource type=\"AudioStream\" path=\"%s\" id=\"%s\"]" % [_emitted[slot], id])
		idx += 1

	lines.append("")
	lines.append("[resource]")
	lines.append("script = ExtResource(\"1_audiolib\")")
	for slot in slots:
		if ids.has(slot):
			lines.append("%s = ExtResource(\"%s\")" % [slot, ids[slot]])
		else:
			lines.append("%s = null" % slot)
	# Mix settings: preserve prior defaults; a touch of pitch variance keeps
	# repeated cursor ticks / footsteps from sounding robotic.
	lines.append("sfx_volume_db = 0.0")
	lines.append("music_volume_db = -6.0")
	lines.append("sfx_pitch_variance = 0.05")
	lines.append("metadata/_custom_type_script = \"%s\"" % SCRIPT_PATH)
	lines.append("")

	var f := FileAccess.open(LIBRARY_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("\n".join(lines))
	f.close()
	return true


# =====================================================================
#  Synth toolkit
# =====================================================================

func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


func _wave(kind: String, phase: float) -> float:
	# phase is in cycles (0..1 repeating).
	match kind:
		"square":
			return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		"triangle":
			# smooth triangle via arcsine of a sine (no hard corners aliasing).
			return (2.0 / PI) * asin(sin(TAU * phase))
		"saw":
			var p := fmod(phase, 1.0)
			return 2.0 * p - 1.0
		_:  # "sine"
			return sin(TAU * phase)


## Fixed-frequency oscillator.
func _osc(freq: float, dur: float, kind: String, amp: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	var inc := freq / SR
	for i in n:
		buf[i] = _wave(kind, phase) * amp
		phase += inc
	return buf


## Frequency-glide oscillator (f0 -> f1 linearly), phase-continuous.
func _glide(f0: float, f1: float, dur: float, kind: String, amp: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(maxi(1, n))
		var f: float = lerp(f0, f1, t)
		phase += f / SR
		buf[i] = _wave(kind, phase) * amp
	return buf


## White noise (deterministic via the seeded rng).
func _noise(dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = _rng.randf_range(-1.0, 1.0) * amp
	return buf


## In-place exponential decay to ~0 over the clip (percussive shaping).
## tau_ratio = fraction of the clip length used as the decay time constant.
func _decay(buf: PackedFloat32Array, tau_ratio: float) -> void:
	var n := buf.size()
	if n == 0:
		return
	var tau: float = max(1.0, tau_ratio * n)
	for i in n:
		buf[i] *= exp(-float(i) / tau)


## In-place linear fade in / fade out (click removal / note shaping).
func _fade(buf: PackedFloat32Array, fin: int, fout: int) -> void:
	var n := buf.size()
	fin = min(fin, n)
	fout = min(fout, n)
	for i in fin:
		buf[i] *= float(i) / float(fin)
	for i in fout:
		buf[n - 1 - i] *= float(i) / float(fout)


## Sum `seg` into `master` starting at sample `at` (grows nothing; clips are
## expected to fit). Out-of-range samples are ignored.
func _add(master: PackedFloat32Array, seg: PackedFloat32Array, at: int) -> void:
	var n := master.size()
	for i in seg.size():
		var j := at + i
		if j >= 0 and j < n:
			master[j] += seg[i]


func _concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out


func _ms(millis: float) -> int:
	return int(millis * 0.001 * SR)


# =====================================================================
#  SFX voices
# =====================================================================

## Short bright blip.
func _make_select() -> PackedFloat32Array:
	var b := _osc(_midi(88), 0.09, "triangle", 0.42)  # E6-ish
	_decay(b, 0.35)
	_fade(b, _ms(2), _ms(20))
	return b


## Soft mid "step".
func _make_move() -> PackedFloat32Array:
	var body := _osc(_midi(50), 0.10, "sine", 0.34)   # low-mid D3
	_decay(body, 0.25)
	var tick := _noise(0.03, 0.10)
	_decay(tick, 0.2)
	var out := PackedFloat32Array()
	out.resize(body.size())
	_add(out, body, 0)
	_add(out, tick, 0)
	_fade(out, _ms(2), _ms(25))
	return out


## Quick noise whoosh / swing.
func _make_attack() -> PackedFloat32Array:
	var b := _noise(0.20, 0.40)
	# swell up then fall away for a "swing past" feel.
	var n := b.size()
	for i in n:
		var t := float(i) / n
		var env: float = sin(PI * t)          # 0 -> 1 -> 0
		b[i] *= env * env
	# a touch of downward tonal glide underneath adds body.
	var body := _glide(_midi(64), _midi(45), 0.20, "saw", 0.12)
	_decay(body, 0.5)
	_add(b, body, 0)
	_fade(b, _ms(4), _ms(20))
	return b


## Short low thud (low sine + noise burst).
func _make_hit() -> PackedFloat32Array:
	var thud := _glide(150.0, 70.0, 0.14, "sine", 0.5)
	_decay(thud, 0.28)
	var crack := _noise(0.06, 0.28)
	_decay(crack, 0.18)
	var out := PackedFloat32Array()
	out.resize(thud.size())
	_add(out, thud, 0)
	_add(out, crack, 0)
	_fade(out, _ms(1), _ms(20))
	return out


## Gentle rising two-note chime (bell-ish triangle + octave shimmer).
func _make_heal() -> PackedFloat32Array:
	var total := _ms(420)
	var out := PackedFloat32Array()
	out.resize(total)
	_add(out, _chime(_midi(72), 0.30, 0.22), 0)          # C5
	_add(out, _chime(_midi(79), 0.30, 0.22), _ms(130))   # G5
	_fade(out, _ms(3), _ms(40))
	return out


## A single soft bell tone: fundamental + quieter octave, exp decay.
func _chime(freq: float, dur: float, amp: float) -> PackedFloat32Array:
	var f := _osc(freq, dur, "triangle", amp)
	var o := _osc(freq * 2.0, dur, "sine", amp * 0.4)
	var out := PackedFloat32Array()
	out.resize(f.size())
	_add(out, f, 0)
	_add(out, o, 0)
	_decay(out, 0.45)
	_fade(out, _ms(4), _ms(30))
	return out


## Short descending tone.
func _make_death() -> PackedFloat32Array:
	var b := _glide(_midi(69), _midi(45), 0.34, "sine", 0.4)  # A4 -> A2
	_decay(b, 0.5)
	_fade(b, _ms(3), _ms(40))
	return b


## 3-note ascending arpeggio (C5-E5-G5).
func _make_turn_start() -> PackedFloat32Array:
	return _arp([72, 76, 79], 0.11, "triangle", 0.34, 0.02)


## Brighter ascending arpeggio (~1s), C5-E5-G5-C6 with a ringing top.
func _make_victory() -> PackedFloat32Array:
	var parts: Array = []
	for m in [72, 76, 79, 84]:
		parts.append(_note(_midi(m), 0.18, "triangle", 0.34, 0.55))
	# sustained, brighter final C6
	var top := _osc(_midi(84), 0.42, "triangle", 0.34)
	var top_h := _osc(_midi(84) * 1.5, 0.42, "sine", 0.10)  # fifth shimmer
	_add(top, top_h, 0)
	_decay(top, 0.6)
	_fade(top, _ms(3), _ms(120))
	parts.append(top)
	return _concat(parts)


## Descending minor arpeggio (~1s): A4-E4-C4-A3 (A-minor feel).
func _make_defeat() -> PackedFloat32Array:
	var parts: Array = []
	for m in [69, 64, 60, 57]:
		parts.append(_note(_midi(m), 0.22, "sine", 0.36, 0.7))
	# low sustained A2 tail
	var tail := _osc(_midi(45), 0.30, "sine", 0.32)
	_decay(tail, 0.55)
	_fade(tail, _ms(3), _ms(120))
	parts.append(tail)
	return _concat(parts)


## Very short tick.
func _make_ui_click() -> PackedFloat32Array:
	var b := _osc(_midi(96), 0.035, "square", 0.26)  # high, brief
	_decay(b, 0.3)
	_fade(b, _ms(1), _ms(8))
	return b


## Helper: one arpeggio note with exp decay (tau_ratio) + shaping fades.
func _note(freq: float, dur: float, kind: String, amp: float, tau_ratio: float) -> PackedFloat32Array:
	var b := _osc(freq, dur, kind, amp)
	_decay(b, tau_ratio)
	_fade(b, _ms(3), _ms(25))
	return b


## Helper: concatenated arpeggio from a list of midi notes.
func _arp(midis: Array, dur: float, kind: String, amp: float, gap_s: float) -> PackedFloat32Array:
	var parts: Array = []
	for m in midis:
		parts.append(_note(_midi(float(m)), dur, kind, amp, 0.5))
		if gap_s > 0.0:
			var silence := PackedFloat32Array()
			silence.resize(int(gap_s * SR))
			parts.append(silence)
	return _concat(parts)


# =====================================================================
#  Music bed (looping)
# =====================================================================

## Heroic 4-bar loop (Am - F - C - G) at ~120 BPM, 2s per bar = 8.0s total.
## Layers per bar: soft bass (root, two hits), sustained triad pad, and an
## eighth-note arpeggio melody. Every voice starts and ends inside the bar with
## per-note fades, so the composite waveform is ~0 at both ends of the loop --
## LOOP_FORWARD (loop_end -> 0) is therefore click-free.
func _make_music() -> PackedFloat32Array:
	var bar := 2.0
	var bar_n := int(bar * SR)
	var total_n := bar_n * 4
	var out := PackedFloat32Array()
	out.resize(total_n)

	# bass root, pad triad (mid), melody triad (upper octave register)
	var prog := [
		{"bass": 45, "triad": [57, 60, 64]},  # Am (A2 ; A3 C4 E4)
		{"bass": 41, "triad": [53, 57, 60]},  # F  (F2 ; F3 A3 C4)
		{"bass": 48, "triad": [52, 55, 60]},  # C  (C3 ; E3 G3 C4)
		{"bass": 43, "triad": [47, 50, 55]},  # G  (G2 ; B2 D3 G3)
	]

	var eighth := bar / 8.0

	for bar_i in prog.size():
		var chord: Dictionary = prog[bar_i]
		var base := bar_i * bar_n
		var triad: Array = chord["triad"]

		# --- Pad: sustained triad, gentle sine, fades in/out within the bar.
		for m in triad:
			var pad := _osc(_midi(float(m)), bar - 0.05, "sine", 0.09)
			_fade(pad, _ms(60), _ms(180))
			_add(out, pad, base)

		# --- Bass: root on beat 1 and beat 3, soft triangle with decay.
		var broot := float(chord["bass"])
		for beat in [0, 2]:
			var bnote := _osc(_midi(broot), 1.0, "triangle", 0.24)
			_decay(bnote, 0.5)
			_fade(bnote, _ms(6), _ms(120))
			_add(out, bnote, base + int(beat * (bar / 4.0) * SR))

		# --- Melody: 8 eighth-notes arpeggiating the triad, bright triangle.
		var mel := [triad[0], triad[1], triad[2], triad[0] + 12,
					triad[2], triad[1], triad[0] + 12, triad[2]]
		for step in mel.size():
			var midi := float(mel[step]) + 12.0  # up an octave for lead register
			var mnote := _osc(_midi(midi), eighth * 0.95, "triangle", 0.16)
			_decay(mnote, 0.6)
			_fade(mnote, _ms(4), _ms(35))
			_add(out, mnote, base + int(step * eighth * SR))

	# Master trim to keep peaks comfortably under clipping (uniform scale is
	# loop-safe -- it doesn't disturb the boundary match).
	for i in out.size():
		out[i] *= 0.72
	return out
