extends SceneTree

## Headless generator for Conquest's MENU MUSIC asset.
##
## Procedurally synthesizes a single ~48s seamlessly-looping "dark forest ambient"
## bed as raw 16-bit mono PCM (22050 Hz, matching dev_scripts/generate_default_audio.gd's
## SFX/battle-theme rate), wraps it in an [AudioStreamWAV], and writes it to
## res://game/audio/music/menu_theme.wav via [method AudioStreamWAV.save_to_wav].
##
## COMPOSITION: a slow D-minor pad (D3-F3-A3, swelling into its relative major
## Bb3-D4-F4 halfway through and back -- a classic i -> VI dark-ambient vamp),
## a continuous sub-bass D2 drone (two barely-detuned sines for a slow analog
## beat + a slow amplitude LFO so it "breathes"), a sparse D-minor-pentatonic
## bell/pluck voice with a long exponential decay (deterministic timing off a
## fixed-seed RNG, like distant chimes), and a very faint continuous noise bed
## (forest-air texture). Everything is mixed, then the whole composite is
## peak-normalized to ~-12 dBFS (0.251 linear).
##
## LOOP TECHNIQUE: crossfade tail-into-head (the alternative this task's brief
## explicitly allows to composing on an exact bar boundary). None of the
## sustained layers here are phase-locked to the loop length -- the drone and
## pad frequencies do not divide evenly into 48s -- so instead of relying on
## sample-exact periodicity, [method _crossfade_loop] blends the LAST
## [constant XFADE_SECONDS] of the composite into a copy of its FIRST
## XFADE_SECONDS, in place, before the buffer is trimmed to its final length.
## The result is not sample-identical across the wrap, but for slow-moving
## pad/drone/noise content (no sharp transients near the seam) it is
## perceptually seamless, which is what LOOP_FORWARD (loop_end -> 0) needs.
##
## WIRING CHOICE: default_audio_library.tres is how every other game sound is
## referenced (an ext_resource per slot; see AudioLibrary.gd's music_menu slot
## and generate_default_audio.gd's own _write_library()), so this generator
## wires the same way: a small, surgical TEXT edit that adds ONE new
## ext_resource pointing at menu_theme.wav and sets music_menu to it, leaving
## every other line untouched. It does NOT touch AudioManager.gd or
## AudioLibrary.gd -- both already fully support this slot (crossfade, scene
## detection, the set_menu_music() runtime override) and need no code change,
## only the data. If the .tres is missing or its shape has drifted so far this
## script's anchors no longer match, the wiring step is skipped with a warning
## printed to stderr -- the .wav is still written (see [method _wire_library]),
## and AudioManager.set_menu_music() remains available as a manual runtime
## fallback for whoever wires the boot path later.
##
## Run headless:
##   godot --headless -s dev_scripts/generate_menu_music.gd
##
## Design notes (mirrors generate_default_audio.gd):
## * Fully DETERMINISTIC -- a fixed-seed RandomNumberGenerator drives every
##   "random" choice (bell timing/pitch), so re-running produces byte-identical
##   output. Idempotent: it always overwrites the same output path with the
##   same bytes, and the .tres wiring step no-ops once already wired (see
##   [method _wire_library]'s "music_menu" substring check).
## * CRITICAL under `-s` (mirrors dev_scripts/soak_battle.gd's own header note):
##   no bare autoload identifiers (GameSettings, AudioManager, ...) and no
##   project class_name references (AudioLibrary, Unit, ...) at compile time --
##   this script needs neither. Everything here is built-in engine API
##   (AudioStreamWAV, FileAccess, DirAccess, RandomNumberGenerator) plus raw
##   text for the .tres, exactly like generate_default_audio.gd.

const SR: int = 22050                          # sample rate (Hz), matches the SFX/battle-theme generator
const OUT_DIR: String = "res://game/audio/music"
const OUT_PATH: String = OUT_DIR + "/menu_theme.wav"
const LIBRARY_PATH: String = "res://game/audio/default_audio_library.tres"

const LOOP_SECONDS: float = 48.0               # total loop length (in the ~45-60s brief)
const XFADE_SECONDS: float = 3.0               # tail-into-head crossfade window
const PEAK_TARGET: float = 0.251               # ~ -12 dBFS linear (10^(-12/20))

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	print("=== Conquest Menu Music Generator ===")
	_rng.seed = 0x0D0F0257  # fixed seed -> deterministic bell timing/pitch

	_ensure_dir(OUT_DIR)

	var buf := _compose()
	_crossfade_loop(buf, int(XFADE_SECONDS * SR))
	_normalize_to_peak(buf, PEAK_TARGET)

	if not _save(buf):
		printerr("FAILED to write %s" % OUT_PATH)
		quit(1)
		return

	var wired := _wire_library()
	var dur: float = float(buf.size()) / float(SR)

	print("\n--- Summary ---")
	print("  wav      : %s" % OUT_PATH)
	print("  duration : %.2fs" % dur)
	print("  library  : %s" % ("wired (music_menu)" if wired else "NOT auto-wired -- see warning above"))
	print("DONE: %s (%.2fs)" % [OUT_PATH, dur])
	quit(0)


# =====================================================================
#  IO
# =====================================================================

func _ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		var err := DirAccess.make_dir_recursive_absolute(path)
		if err != OK:
			push_warning("Could not create dir %s (err %d)" % [path, err])


func _save(buf: PackedFloat32Array) -> bool:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = _to_bytes(buf)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = buf.size()

	var err := wav.save_to_wav(OUT_PATH)
	if err != OK:
		printerr("  save failed: %s (err %d)" % [OUT_PATH, err])
		return false
	print("  emitted %s  %d samples (%.2fs)  [loop]"
		% [OUT_PATH.get_file(), buf.size(), float(buf.size()) / SR])
	return true


func _to_bytes(buf: PackedFloat32Array) -> PackedByteArray:
	var n := buf.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var s := clampf(buf[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(round(s * 32767.0)))
	return bytes


## Surgical text edit of default_audio_library.tres: add ONE ext_resource for
## menu_theme.wav and point music_menu at it. Idempotent (a "music_menu"
## substring already present means a prior run already wired it -- skipped,
## not duplicated) and non-fatal on any shape it does not recognise (the .wav
## is already safely on disk by the time this runs; a missing/unrecognised
## .tres just means the caller wires it another way -- see class doc).
func _wire_library() -> bool:
	if not FileAccess.file_exists(LIBRARY_PATH):
		push_warning(("%s not found; skipping library wiring (run generate_default_audio.gd first, "
			+ "or wire menu_theme.wav in some other way -- see AudioManager.set_menu_music()).") % LIBRARY_PATH)
		return false

	var f := FileAccess.open(LIBRARY_PATH, FileAccess.READ)
	if f == null:
		push_warning("Could not open %s for reading; skipping library wiring." % LIBRARY_PATH)
		return false
	var text := f.get_as_text()
	f.close()

	if text.find("music_menu") != -1:
		print("  library already references music_menu -- leaving %s untouched." % LIBRARY_PATH)
		return true

	# 1. Bump load_steps by one (one more ext_resource is being added).
	var re := RegEx.new()
	re.compile("load_steps=(\\d+)")
	var m := re.search(text)
	if m == null:
		push_warning("Could not find load_steps= in %s; skipping library wiring." % LIBRARY_PATH)
		return false
	var next_id := int(m.get_string(1))
	text = text.replace("load_steps=%d" % next_id, "load_steps=%d" % (next_id + 1))

	# 2. Insert a new ext_resource line right after the LAST existing one.
	var lines: PackedStringArray = text.split("\n")
	var last_ext_idx := -1
	for i in lines.size():
		if lines[i].begins_with("[ext_resource"):
			last_ext_idx = i
	if last_ext_idx == -1:
		push_warning("No [ext_resource] lines found in %s; skipping library wiring." % LIBRARY_PATH)
		return false
	var ext_id := "%d_music_menu" % next_id
	var ext_line := "[ext_resource type=\"AudioStream\" path=\"res://game/audio/music/menu_theme.wav\" id=\"%s\"]" % ext_id
	lines.insert(last_ext_idx + 1, ext_line)

	# 3. Insert the music_menu = ExtResource(...) field. Anchor on music_battle's
	#    own field line when present (keeps it grouped with the other Music slot);
	#    otherwise fall back to just before sfx_volume_db, or finally right after
	#    `script = ExtResource(...)` -- whichever anchor this .tres actually has.
	var field_line := "music_menu = ExtResource(\"%s\")" % ext_id
	var insert_after := -1
	for i in lines.size():
		if lines[i].begins_with("music_battle = "):
			insert_after = i
			break
	if insert_after == -1:
		for i in lines.size():
			if lines[i].begins_with("sfx_volume_db"):
				insert_after = i - 1
				break
	if insert_after == -1:
		for i in lines.size():
			if lines[i].begins_with("script = ExtResource"):
				insert_after = i
				break
	if insert_after == -1:
		push_warning("Could not find a field anchor in %s; skipping library wiring." % LIBRARY_PATH)
		return false
	lines.insert(insert_after + 1, field_line)

	var out := FileAccess.open(LIBRARY_PATH, FileAccess.WRITE)
	if out == null:
		push_warning("Could not open %s for writing; skipping library wiring." % LIBRARY_PATH)
		return false
	out.store_string("\n".join(lines))
	out.close()
	print("  wired %s -> music_menu (%s)" % [LIBRARY_PATH, ext_id])
	return true


# =====================================================================
#  Synth toolkit (self-contained -- see class doc on why nothing is shared
#  with generate_default_audio.gd across a -s boundary)
# =====================================================================

func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


func _wave(kind: String, phase: float) -> float:
	match kind:
		"triangle":
			return (2.0 / PI) * asin(sin(TAU * phase))
		_:  # "sine"
			return sin(TAU * phase)


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


func _noise(dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = _rng.randf_range(-1.0, 1.0) * amp
	return buf


## In-place exponential decay to ~0 over the clip (tau_ratio = fraction of the
## clip length used as the decay time constant -- smaller = faster decay).
func _decay(buf: PackedFloat32Array, tau_ratio: float) -> void:
	var n := buf.size()
	if n == 0:
		return
	var tau: float = max(1.0, tau_ratio * n)
	for i in n:
		buf[i] *= exp(-float(i) / tau)


## In-place linear fade in / fade out (click removal / envelope shaping).
func _fade(buf: PackedFloat32Array, fin: int, fout: int) -> void:
	var n := buf.size()
	fin = mini(fin, n)
	fout = mini(fout, n)
	for i in fin:
		buf[i] *= float(i) / float(fin)
	for i in fout:
		buf[n - 1 - i] *= float(i) / float(fout)


## Sum `seg` into `master` starting at sample `at`. Out-of-range samples of
## `seg` are ignored (lets a note's tail run past the master's own end safely).
func _add(master: PackedFloat32Array, seg: PackedFloat32Array, at: int) -> void:
	var n := master.size()
	for i in seg.size():
		var j := at + i
		if j >= 0 and j < n:
			master[j] += seg[i]


func _ms(millis: float) -> int:
	return int(millis * 0.001 * SR)


# =====================================================================
#  Composition
# =====================================================================

## Assemble the whole ~48s composite: drone + pad + bells + noise, all summed
## into one master buffer of exactly LOOP_SECONDS. Loop-safety (the crossfade)
## and level (peak normalization) are applied by the caller afterward.
func _compose() -> PackedFloat32Array:
	var total_n := int(LOOP_SECONDS * SR)
	var out := PackedFloat32Array()
	out.resize(total_n)

	_add(out, _make_drone(LOOP_SECONDS), 0)
	_add_pad_sections(out)
	_add_bells(out)
	_add(out, _make_air(LOOP_SECONDS), 0)

	return out


## Continuous low D2 drone (73.42 Hz): two barely-detuned sines for a slow
## analog beat, under a slow amplitude LFO so it feels like it is breathing
## rather than a static tone. Runs the ENTIRE loop -- its frequency does not
## evenly divide LOOP_SECONDS, which is exactly why the caller crossfades the
## final composite rather than relying on this oscillator's own phase to close.
func _make_drone(dur: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var root := _midi(38.0)         # D2
	var detuned := root * 1.0035    # a few cents sharp -- slow beating, not a chorus warble
	var phase_a := 0.0
	var phase_b := 0.0
	var inc_a := root / SR
	var inc_b := detuned / SR
	# Slow amplitude "breathing" LFO, deliberately NOT period-locked to
	# LOOP_SECONDS (24s period over a 48s loop happens to close evenly, which
	# is a nice bonus, but the crossfade is what actually guarantees the seam).
	var lfo_period := 24.0
	for i in n:
		var t := float(i) / SR
		var lfo: float = 0.72 + 0.28 * sin(TAU * t / lfo_period)
		var s: float = (sin(TAU * phase_a) + sin(TAU * phase_b)) * 0.5
		buf[i] = s * 0.05 * lfo
		phase_a += inc_a
		phase_b += inc_b
	# Only the very start needs a fade-in guard (silence before playback
	# begins); the loop seam itself is handled by the crossfade, not by fading
	# this layer to zero at dur -- fading it there would make the last couple
	# of seconds of every loop noticeably duck, which is not what "continuous
	# drone" should sound like.
	_fade(buf, _ms(400), 0)
	return buf


## The two-chord dark-ambient vamp: D minor (i) for the first half of the
## loop, its relative major Bb (VI) for the second half, each a sustained
## triad with a multi-second swell in and out so the change reads as a slow
## harmonic tide rather than a cut. The static D drone underneath both halves
## colours the Bb chord as a Bb(add9)-ish sonority -- intentional; a drone
## pedal under the relative major is a common dark-ambient move.
func _add_pad_sections(out: PackedFloat32Array) -> void:
	var half := LOOP_SECONDS / 2.0
	var dm_triad := [50.0, 53.0, 57.0]   # D3, F3, A3
	var bb_triad := [46.0, 50.0, 53.0]   # Bb2, D3, F3
	_add_pad_chord(out, dm_triad, 0.0, half)
	_add_pad_chord(out, bb_triad, half, LOOP_SECONDS - half)


## One sustained triad: each voice is a soft sine, swelled in over the first
## ~1/6 of its span and swelled out over the last ~1/6, so three simultaneous
## voices never attack/release as a single hard edge.
func _add_pad_chord(out: PackedFloat32Array, triad: Array, start_s: float, span_s: float) -> void:
	var swell: float = clampf(span_s / 6.0, 1.5, 4.0)
	for m in triad:
		var voice := _osc(_midi(float(m)), span_s, "sine", 0.05)
		_fade(voice, _ms(swell * 1000.0), _ms(swell * 1000.0))
		_add(out, voice, int(start_s * SR))


## Sparse D-minor-pentatonic bells/plucks (distant-chime feel): deterministic
## timing off the fixed-seed RNG, roughly one every 3.5-7.5s, each a soft
## triangle fundamental + a quiet octave-up sine, LONG exponential decay so a
## single strike rings for several seconds.
func _add_bells(out: PackedFloat32Array) -> void:
	var pentatonic := [62.0, 65.0, 67.0, 69.0, 72.0, 74.0, 77.0, 79.0, 81.0]  # D4..A5, D minor pentatonic
	var t := 2.5
	# Stop early enough that even the LAST bell's full ~4.5s decay (see
	# _forest_bell) finishes before LOOP_SECONDS -- otherwise _add() would
	# silently truncate its tail mid-ring right where the crossfade lives.
	while t < LOOP_SECONDS - 5.0:
		var midi: float = float(pentatonic[_rng.randi_range(0, pentatonic.size() - 1)])
		var amp: float = _rng.randf_range(0.05, 0.09)
		_add(out, _forest_bell(_midi(midi), amp), int(t * SR))
		t += _rng.randf_range(3.5, 7.5)


## A single long-decaying bell tone: fundamental (triangle) + a quiet octave
## partial (sine), both under one shared exponential decay envelope.
func _forest_bell(freq: float, amp: float) -> PackedFloat32Array:
	var dur := 4.5
	var fund := _osc(freq, dur, "triangle", amp)
	var octave := _osc(freq * 2.0, dur, "sine", amp * 0.35)
	var out := PackedFloat32Array()
	out.resize(fund.size())
	_add(out, fund, 0)
	_add(out, octave, 0)
	_decay(out, 0.30)  # long ring: ~30% of the 4.5s buffer as the time constant
	_fade(out, _ms(8), _ms(60))
	return out


## Very faint continuous noise bed ("forest air"): raw white noise at a low
## fixed amplitude under its own slow LFO, independent phase from the drone's
## so the two never lock into a single obvious pulse.
func _make_air(dur: float) -> PackedFloat32Array:
	var buf := _noise(dur, 0.035)
	var n := buf.size()
	var lfo_period := 17.0
	for i in n:
		var t := float(i) / SR
		var lfo: float = 0.6 + 0.4 * sin(TAU * t / lfo_period + 1.7)
		buf[i] *= lfo
	_fade(buf, _ms(400), 0)
	return buf


# =====================================================================
#  Loop safety + level
# =====================================================================

## Crossfade the tail into a copy of the head, IN PLACE, so the buffer's own
## end already resembles its own start by the time LOOP_FORWARD wraps
## loop_end back to sample 0. See the class doc for why this (rather than
## bar-exact composition) is this piece's loop technique.
func _crossfade_loop(buf: PackedFloat32Array, xfade_n: int) -> void:
	var n := buf.size()
	xfade_n = mini(xfade_n, n / 4)
	if xfade_n <= 0:
		return
	var head := PackedFloat32Array()
	head.resize(xfade_n)
	for i in xfade_n:
		head[i] = buf[i]
	for i in xfade_n:
		var t := float(i) / float(xfade_n)  # 0 at the fade's start -> 1 at the buffer's last sample
		var tail_idx := n - xfade_n + i
		buf[tail_idx] = buf[tail_idx] * (1.0 - t) + head[i] * t


## Scale the whole buffer so its absolute peak lands exactly on [param target]
## (a no-op if the buffer is silent). Normalizing to a measured peak, rather
## than hand-tuning each layer's amplitude to add up correctly, is what makes
## the "-12 dBFS peak" target exact regardless of how the layers happen to sum.
func _normalize_to_peak(buf: PackedFloat32Array, target: float) -> void:
	var peak := 0.0
	for s in buf:
		peak = max(peak, absf(s))
	if peak <= 0.0001:
		return
	var scale := target / peak
	for i in buf.size():
		buf[i] *= scale
