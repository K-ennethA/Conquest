extends SceneTree

## Headless generator for Conquest's MENU MUSIC asset.
##
## Procedurally synthesizes a single ~48s seamlessly-looping "dark forest ambient"
## bed as raw 16-bit mono PCM (44100 Hz), wraps it in an [AudioStreamWAV], and
## writes it to res://game/audio/music/menu_theme.wav via
## [method AudioStreamWAV.save_to_wav].
##
## COMPOSITION: a slow D-minor pad (D3-F3-A3, swelling into its relative major
## Bb3-D4-F4 halfway through and back -- a classic i -> VI dark-ambient vamp),
## a continuous sub-bass D2 drone (two barely-detuned sines for a slow analog
## beat + a slow amplitude LFO so it "breathes"), a sparse D-minor-pentatonic
## bell/pluck voice with a long exponential decay (deterministic timing off a
## fixed-seed RNG, like distant chimes), and a very faint LOWPASSED noise bed
## (forest-air texture). Everything is mixed, then the whole composite is
## peak-normalized to ~-16 dBFS ([constant PEAK_TARGET]).
##
## WHY IT NO LONGER HISSES/CRACKLES (the "staticky" report on the first pass):
## three separate causes, all fixed here.
##  1. ALIASING. Every voice is now strictly BAND-LIMITED -- pure sines plus at
##     most one gentle 2nd harmonic ([constant BELL_H2]). The old bell used an
##     `asin(sin())` triangle, whose harmonic series runs past Nyquist and folds
##     back as inharmonic buzz; that fold-back IS the "static". Nothing in this
##     file generates a naive saw/square/triangle any more, and the sample rate
##     doubled to 44100 so even the top bell's 2nd harmonic (1760 Hz) sits far
##     below Nyquist.
##  2. HARD ATTACKS. A bell that jumps from silence to full amplitude in one
##     sample is a step function -- broadband click energy on every strike. Each
##     bell now opens through a [constant BELL_ATTACK_MS] raised-cosine attack
##     ([method _attack_cos]), and every swell/fade in the piece uses the same
##     raised-cosine shape ([method _fade]) rather than a linear ramp, so no
##     layer ever starts or stops with a corner in its envelope.
##  3. A BROADBAND NOISE BED. Raw white noise sat at 0.035 and reached all the
##     way to Nyquist, which reads as tape hiss. It is now a third of that
##     amplitude and runs through a one-pole lowpass at [constant AIR_LP_HZ], so
##     it is a low "air" movement rather than a hiss.
## Level is the fourth half of the same complaint: the peak target dropped from
## -12 to -16 dBFS here, and AudioManager's own music trim dropped to -10 dB, so
## the menu bed sits well under the SFX instead of on top of them.
##
## HEADROOM: [method _report_headroom] measures the composite BEFORE normalizing
## and prints the true peak plus a count of any samples outside +/-1.0. Because
## every layer's amplitude is fixed and small (drone <= 0.05, pad 3 x 0.05,
## a bell <= ~0.12, air <= 0.010) the sum cannot approach 1.0, so that count must
## print 0 -- if it ever does not, a layer's amplitude was raised too far and the
## mix is clipping before normalization can rescale it.
##
## LOOP TECHNIQUE: crossfade tail-into-head. None of the sustained layers here
## are phase-locked to the loop length -- the drone and pad frequencies do not
## divide evenly into 48s -- so instead of relying on sample-exact periodicity,
## [method _crossfade_loop] blends the LAST [constant XFADE_SECONDS] of the
## composite into a copy of its FIRST XFADE_SECONDS, in place. The result is not
## sample-identical across the wrap, but for slow-moving pad/drone/air content
## (no sharp transients near the seam) it is perceptually seamless, which is what
## LOOP_FORWARD (loop_end -> 0) needs.
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
##   "random" choice (bell timing/pitch, the air bed's noise), so re-running
##   produces byte-identical output. Idempotent: it always overwrites the same
##   output path with the same bytes, and the .tres wiring step no-ops once
##   already wired (see [method _wire_library]'s "music_menu" substring check).
## * CRITICAL under `-s` (mirrors dev_scripts/soak_battle.gd's own header note):
##   no bare autoload identifiers (GameSettings, AudioManager, ...) and no
##   project class_name references (AudioLibrary, Unit, ...) at compile time --
##   this script needs neither. Everything here is built-in engine API
##   (AudioStreamWAV, FileAccess, DirAccess, RandomNumberGenerator) plus raw
##   text for the .tres, exactly like generate_default_audio.gd.

const SR: int = 44100                          # sample rate (Hz) -- full-band, so nothing aliases
const OUT_DIR: String = "res://game/audio/music"
const OUT_PATH: String = OUT_DIR + "/menu_theme.wav"
const LIBRARY_PATH: String = "res://game/audio/default_audio_library.tres"

const LOOP_SECONDS: float = 48.0               # total loop length (in the ~45-60s brief)
const XFADE_SECONDS: float = 3.0               # tail-into-head crossfade window
const PEAK_TARGET: float = 0.158               # ~ -16 dBFS linear (10^(-16/20))

## Bell voicing. A single gentle 2nd harmonic (one octave up) is the ONLY partial
## above the fundamental -- enough to read as a struck bell rather than a test
## tone, with nothing anywhere near Nyquist to fold back as buzz.
const BELL_H2: float = 0.28                    # 2nd-harmonic amplitude, relative to the fundamental
const BELL_ATTACK_MS: float = 12.0             # raised-cosine attack (brief calls for 5-15 ms)
const BELL_RELEASE_MS: float = 120.0           # raised-cosine tail, so a truncated ring never steps to 0

## Forest-air bed. One-pole lowpassed at AIR_LP_HZ so it is low movement rather
## than broadband hiss, and at a third of the amplitude the first pass used.
const AIR_AMP: float = 0.010
const AIR_LP_HZ: float = 800.0

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	print("=== Conquest Menu Music Generator ===")
	_rng.seed = 0x0D0F0257  # fixed seed -> deterministic bell timing/pitch + air noise

	_ensure_dir(OUT_DIR)

	var buf := _compose()
	_crossfade_loop(buf, int(XFADE_SECONDS * SR))
	var raw_peak := _report_headroom(buf)
	_normalize_to_peak(buf, PEAK_TARGET)

	if not _save(buf):
		printerr("FAILED to write %s" % OUT_PATH)
		quit(1)
		return

	var wired := _wire_library()
	var dur: float = float(buf.size()) / float(SR)

	print("\n--- Summary ---")
	print("  wav      : %s" % OUT_PATH)
	print("  rate     : %d Hz mono 16-bit" % SR)
	print("  duration : %.2fs" % dur)
	print("  pre-norm peak : %.4f (%.2f dBFS)" % [raw_peak, _db(raw_peak)])
	print("  final peak    : %.4f (%.2f dBFS)" % [PEAK_TARGET, _db(PEAK_TARGET)])
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


## Linear amplitude -> dBFS, for the headroom report only.
func _db(linear: float) -> float:
	if linear <= 0.0000001:
		return -INF
	return 20.0 * (log(linear) / log(10.0))


## A pure sine at [param freq]. The ONLY oscillator in this file: any waveform
## with a richer harmonic series (saw/square/`asin(sin())` triangle) is generated
## by naive sampling here, which aliases -- see the class doc's cause (1). The
## phase accumulator wraps every cycle so 48s of samples never erode its
## precision.
func _osc(freq: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	var inc := freq / SR
	for i in n:
		buf[i] = sin(TAU * phase) * amp
		phase += inc
		if phase >= 1.0:
			phase -= 1.0
	return buf


## White noise run through a ONE-POLE LOWPASS at [param cutoff_hz]. The filter is
## the whole point: unfiltered noise reaches Nyquist and reads as tape hiss (the
## class doc's cause (3)). Gain is re-measured after filtering and rescaled back
## to [param amp], because a one-pole at 800 Hz removes most of white noise's
## energy and the bed would otherwise vanish.
func _noise_lp(dur: float, amp: float, cutoff_hz: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var a: float = 1.0 - exp(-TAU * cutoff_hz / float(SR))
	var y := 0.0
	var peak := 0.0
	for i in n:
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		buf[i] = y
		peak = max(peak, absf(y))
	if peak > 0.0001:
		var scale := amp / peak
		for i in n:
			buf[i] *= scale
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


## In-place RAISED-COSINE fade in / fade out. Deliberately not linear: a linear
## ramp has a corner (a discontinuity in the envelope's derivative) at both ends,
## which on a short fade is audible as a tick. `0.5 - 0.5*cos(PI*t)` leaves the
## envelope flat at both ends, so every swell and every note edge in the piece is
## click-free. Pass 0 for either side to skip it.
func _fade(buf: PackedFloat32Array, fin: int, fout: int) -> void:
	var n := buf.size()
	fin = mini(fin, n)
	fout = mini(fout, n)
	for i in fin:
		var t: float = float(i) / float(fin)
		buf[i] *= 0.5 - 0.5 * cos(PI * t)
	for i in fout:
		var t: float = float(i) / float(fout)
		buf[n - 1 - i] *= 0.5 - 0.5 * cos(PI * t)


## In-place raised-cosine ATTACK over the first [param n_samples] only. Applied
## AFTER the decay envelope (which starts at full amplitude on sample 0), so a
## struck note ramps up instead of stepping -- the class doc's cause (2).
func _attack_cos(buf: PackedFloat32Array, n_samples: int) -> void:
	var n: int = mini(n_samples, buf.size())
	for i in n:
		var t: float = float(i) / float(n)
		buf[i] *= 0.5 - 0.5 * cos(PI * t)


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

## Assemble the whole ~48s composite: drone + pad + bells + air, all summed
## into one master buffer of exactly LOOP_SECONDS. Loop-safety (the crossfade),
## the headroom check and level (peak normalization) are applied by the caller
## afterward.
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
		if phase_a >= 1.0:
			phase_a -= 1.0
		phase_b += inc_b
		if phase_b >= 1.0:
			phase_b -= 1.0
	# Only the very start needs a fade-in guard (silence before playback
	# begins); the loop seam itself is handled by the crossfade, not by fading
	# this layer to zero at dur -- fading it there would make the last couple
	# of seconds of every loop noticeably duck, which is not what "continuous
	# drone" should sound like.
	_fade(buf, _ms(600), 0)
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


## One sustained triad: each voice is a pure sine, swelled in over the first
## ~1/6 of its span and swelled out over the last ~1/6 (raised-cosine, see
## [method _fade]), so three simultaneous voices never attack or release as a
## single hard edge.
func _add_pad_chord(out: PackedFloat32Array, triad: Array, start_s: float, span_s: float) -> void:
	var swell: float = clampf(span_s / 6.0, 1.5, 4.0)
	for m in triad:
		var voice := _osc(_midi(float(m)), span_s, 0.05)
		_fade(voice, _ms(swell * 1000.0), _ms(swell * 1000.0))
		_add(out, voice, int(start_s * SR))


## Sparse D-minor-pentatonic bells/plucks (distant-chime feel): deterministic
## timing off the fixed-seed RNG, roughly one every 3.5-7.5s, each a soft sine
## fundamental + one quiet octave partial, LONG exponential decay so a single
## strike rings for several seconds.
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


## A single long-decaying bell tone: a sine fundamental plus one quiet octave
## partial ([constant BELL_H2]) under a shared exponential decay, then opened
## through a [constant BELL_ATTACK_MS] raised-cosine attack and closed with a
## matching release. Attack order matters: _decay() starts at full amplitude on
## sample 0, so the attack has to be applied on top of it, not before it.
func _forest_bell(freq: float, amp: float) -> PackedFloat32Array:
	var dur := 4.5
	var out := PackedFloat32Array()
	out.resize(int(dur * SR))
	_add(out, _osc(freq, dur, amp), 0)
	_add(out, _osc(freq * 2.0, dur, amp * BELL_H2), 0)
	_decay(out, 0.30)  # long ring: ~30% of the 4.5s buffer as the time constant
	_attack_cos(out, _ms(BELL_ATTACK_MS))
	_fade(out, 0, _ms(BELL_RELEASE_MS))
	return out


## Very faint lowpassed noise bed ("forest air") under its own slow LFO, with an
## independent phase from the drone's so the two never lock into a single obvious
## pulse. See [method _noise_lp] and the class doc's cause (3) for why it is
## filtered rather than raw white noise.
func _make_air(dur: float) -> PackedFloat32Array:
	var buf := _noise_lp(dur, AIR_AMP, AIR_LP_HZ)
	var n := buf.size()
	var lfo_period := 17.0
	for i in n:
		var t := float(i) / SR
		var lfo: float = 0.6 + 0.4 * sin(TAU * t / lfo_period + 1.7)
		buf[i] *= lfo
	_fade(buf, _ms(600), 0)
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


## Measure the composite BEFORE normalization and report it. Returns the true
## peak and prints a clip count that must be 0. It has to run BEFORE
## [method _normalize_to_peak]: normalization scales the whole buffer down, so a
## layer summing past +/-1.0 would look perfectly clean afterwards even though
## the mix that produced it was over budget. Any non-zero count here means a
## layer amplitude was raised too far -- see the class doc's HEADROOM note.
func _report_headroom(buf: PackedFloat32Array) -> float:
	var peak := 0.0
	var clipped := 0
	for s in buf:
		var a := absf(s)
		if a > peak:
			peak = a
		if a > 1.0:
			clipped += 1
	print("  headroom : pre-normalize peak %.4f (%.2f dBFS), %d sample(s) outside +/-1.0"
		% [peak, _db(peak), clipped])
	if clipped > 0:
		printerr("  WARNING: %d sample(s) exceeded +/-1.0 before normalization -- a layer amplitude is too high." % clipped)
	return peak


## Scale the whole buffer so its absolute peak lands exactly on [param target]
## (a no-op if the buffer is silent). Normalizing to a measured peak, rather
## than hand-tuning each layer's amplitude to add up correctly, is what makes
## the "-16 dBFS peak" target exact regardless of how the layers happen to sum.
func _normalize_to_peak(buf: PackedFloat32Array, target: float) -> void:
	var peak := 0.0
	for s in buf:
		peak = max(peak, absf(s))
	if peak <= 0.0001:
		return
	var scale := target / peak
	for i in buf.size():
		buf[i] *= scale
