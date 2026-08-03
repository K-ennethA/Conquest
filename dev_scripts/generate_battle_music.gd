extends SceneTree

## Headless generator for Conquest's BATTLE MUSIC asset.
##
## Procedurally synthesizes a 38.4s seamlessly-looping "tense mid-tempo march" bed as raw
## 16-bit mono PCM (44100 Hz), wraps it in an [AudioStreamWAV], and writes it to
## res://game/audio/music/battle_theme.wav via [method AudioStreamWAV.save_to_wav].
##
## WHY THIS EXISTS. A battle_theme.wav already shipped, but it was the FIRST-PASS asset from
## generate_default_audio.gd: 8 seconds long, 22050 Hz, and built from naive sampled waveforms
## -- exactly the aliasing/hard-attack recipe that produced the "staticky" report the menu
## theme was regenerated to fix (see [script generate_menu_music.gd]'s class docs, causes 1-3).
## This file replaces it with the same BAND-LIMITED pipeline: pure sines plus at most one
## gentle 2nd harmonic, raised-cosine attacks and fades on every voice, 44100 Hz, and a
## measured peak normalization to [constant PEAK_TARGET] (~ -16 dBFS) so the bed sits under the
## SFX rather than on top of them.
##
## DISTINCT FROM THE MENU THEME, deliberately. The menu is a slow, static, drifting D-minor
## dark-ambient pad with no pulse. This is its opposite in every axis that matters:
##   * KEY      E natural minor (menu: D minor) -- a different tonal centre, so the two never
##              sound like the same cue at different tempos.
##   * PULSE    a steady 100 BPM eighth-note low "heartbeat" ([method _pulse]) plus a driving
##              eighth-note ostinato ([method _add_ostinato]). The menu has NO rhythm at all;
##              this one is carried by it.
##   * HARMONY  a four-section i - VI - iv - V vamp (Em - C - Am - B) that keeps resolving and
##              re-tensing, versus the menu's single two-chord i -> VI tide.
##   * TENSION  a sparse high minor-2nd dyad ([method _add_tension_stabs]) -- two sine tones a
##              semitone apart, which beat against each other -- placed on the section seams.
##   * NO AIR BED. The menu's lowpassed forest noise is its signature texture; leaving it out
##              here keeps the two beds obviously different instruments.
##
## HEADROOM: [method _report_headroom] measures the composite BEFORE normalizing and prints
## the true peak plus a count of any samples outside +/-1.0. Every layer's amplitude is fixed
## and small (drone <= 0.05, pulse <= 0.14, ostinato <= 0.09, pad 3 x 0.045, a stab <= 0.05),
## so the sum cannot approach 1.0 and that count MUST print 0 -- if it ever does not, a layer
## amplitude was raised too far and the mix is clipping before normalization can rescale it.
##
## LOOP TECHNIQUE: the tempo grid divides [constant LOOP_SECONDS] exactly (100 BPM, 16 bars of
## 4/4 = 38.4s), so every rhythmic voice closes on the seam by construction. The SUSTAINED
## layers (drone, pad) do not -- their frequencies do not divide evenly into 38.4s -- so the
## composite still gets the menu generator's tail-into-head [method _crossfade_loop], which is
## what actually guarantees LOOP_FORWARD (loop_end -> 0) is inaudible.
##
## WIRING: default_audio_library.tres ALREADY references
## res://game/audio/music/battle_theme.wav as its `music_battle` slot (see that .tres), and
## this script writes to that exact path -- so overwriting the file re-skins battle music with
## no .tres edit at all. [method _verify_library] only CHECKS that the reference is still
## there and warns if it is not; it never rewrites the library, because unlike the menu slot
## there is nothing to add.
##
## Run headless:
##   godot --headless -s dev_scripts/generate_battle_music.gd
##
## Design notes (mirrors generate_menu_music.gd):
## * Fully DETERMINISTIC -- a fixed-seed RandomNumberGenerator drives every "random" choice, so
##   re-running produces byte-identical output. Idempotent: it always overwrites the same
##   output path with the same bytes.
## * CRITICAL under `-s`: no bare autoload identifiers (GameSettings, AudioManager, ...) and no
##   project class_name references (AudioLibrary, Unit, ...) at compile time. Everything here
##   is built-in engine API plus raw text, exactly like generate_menu_music.gd.

const SR: int = 44100                          # sample rate (Hz) -- full-band, so nothing aliases
const OUT_DIR: String = "res://game/audio/music"
const OUT_PATH: String = OUT_DIR + "/battle_theme.wav"
const LIBRARY_PATH: String = "res://game/audio/default_audio_library.tres"

## 100 BPM, 4/4. Chosen so the grid closes on the loop exactly: beat 0.6s, bar 2.4s,
## 16 bars = 38.4s. "Mid-tempo" per the brief -- driving, but not a chase cue.
const BPM: float = 100.0
const BEAT: float = 60.0 / BPM                 # 0.60s
const BAR: float = BEAT * 4.0                  # 2.40s
const BARS: int = 16
const LOOP_SECONDS: float = BAR * float(BARS)  # 38.40s
const XFADE_SECONDS: float = 2.4               # one bar of tail-into-head crossfade
const PEAK_TARGET: float = 0.158               # ~ -16 dBFS linear (10^(-16/20))

## Voice amplitudes. Deliberately constants rather than magic numbers inline: the HEADROOM
## note above reasons about their SUM, and that argument has to stay checkable.
const DRONE_AMP: float = 0.050
const PULSE_AMP: float = 0.140
const OSTINATO_AMP: float = 0.090
const PAD_AMP: float = 0.045
const STAB_AMP: float = 0.050

## Every struck voice opens through a raised-cosine attack of this length. A note that jumps
## from silence to full amplitude in one sample is a step function -- broadband click energy on
## every strike, which is what reads as "static" (generate_menu_music.gd's cause 2).
const ATTACK_MS: float = 8.0
## Matching raised-cosine release, so a truncated tail never steps to zero either.
const RELEASE_MS: float = 60.0
## The single gentle 2nd harmonic (one octave up) carried by the ostinato and the stabs. The
## ONLY partial above any fundamental in this file; at 0.22 it reads as "plucked" rather than
## as a test tone, and even the top voice's octave sits far below Nyquist.
const H2: float = 0.22

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	print("=== Conquest Battle Music Generator ===")
	_rng.seed = 0x0B47713E  # fixed seed -> deterministic stab placement

	_ensure_dir(OUT_DIR)

	var buf := _compose()
	_crossfade_loop(buf, int(XFADE_SECONDS * SR))
	var raw_peak := _report_headroom(buf)
	_normalize_to_peak(buf, PEAK_TARGET)

	if not _save(buf):
		printerr("FAILED to write %s" % OUT_PATH)
		quit(1)
		return

	var wired := _verify_library()
	var dur: float = float(buf.size()) / float(SR)

	print("\n--- Summary ---")
	print("  wav      : %s" % OUT_PATH)
	print("  rate     : %d Hz mono 16-bit" % SR)
	print("  tempo    : %.0f BPM, %d bars of 4/4" % [BPM, BARS])
	print("  duration : %.2fs" % dur)
	print("  pre-norm peak : %.4f (%.2f dBFS)" % [raw_peak, _db(raw_peak)])
	print("  final peak    : %.4f (%.2f dBFS)" % [PEAK_TARGET, _db(PEAK_TARGET)])
	print("  library  : %s" % ("music_battle already points here" if wired else "NOT referenced -- see warning above"))
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


## CHECK ONLY -- unlike generate_menu_music.gd's _wire_library, this never edits the .tres.
## The `music_battle` slot has referenced this exact path since the first audio pass, so
## overwriting the .wav is the whole wiring step; all that is worth doing here is proving the
## reference still exists, so a future .tres reshuffle that dropped it is reported rather than
## silently producing an asset nothing loads.
func _verify_library() -> bool:
	if not FileAccess.file_exists(LIBRARY_PATH):
		push_warning("%s not found; battle_theme.wav is on disk but nothing references it." % LIBRARY_PATH)
		return false
	var f := FileAccess.open(LIBRARY_PATH, FileAccess.READ)
	if f == null:
		push_warning("Could not open %s for reading; cannot verify the music_battle slot." % LIBRARY_PATH)
		return false
	var text := f.get_as_text()
	f.close()
	if text.find("music_battle") == -1 or text.find("music/battle_theme.wav") == -1:
		push_warning(("%s no longer references music/battle_theme.wav as music_battle -- "
			+ "re-point the slot, or the generated asset will never be loaded.") % LIBRARY_PATH)
		return false
	return true


# =====================================================================
#  Synth toolkit (self-contained -- see the class doc on why nothing is
#  shared with the other generators across a `-s` boundary)
# =====================================================================

func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


## Linear amplitude -> dBFS, for the headroom report only.
func _db(linear: float) -> float:
	if linear <= 0.0000001:
		return -INF
	return 20.0 * (log(linear) / log(10.0))


## A pure sine at [param freq]. The ONLY oscillator in this file: any waveform with a richer
## harmonic series (saw/square/`asin(sin())` triangle) generated by naive sampling ALIASES,
## and that fold-back is what the first-pass battle theme sounded like. The phase accumulator
## wraps every cycle so a 38s render never erodes its precision.
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


## In-place exponential decay to ~0 over the clip (tau_ratio = fraction of the clip length
## used as the decay time constant -- smaller = faster decay).
func _decay(buf: PackedFloat32Array, tau_ratio: float) -> void:
	var n := buf.size()
	if n == 0:
		return
	var tau: float = max(1.0, tau_ratio * n)
	for i in n:
		buf[i] *= exp(-float(i) / tau)


## In-place RAISED-COSINE fade in / fade out. Deliberately not linear: a linear ramp has a
## corner in the envelope at both ends, which on a short fade is audible as a tick.
## `0.5 - 0.5*cos(PI*t)` leaves the envelope flat at both ends. Pass 0 to skip either side.
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


## In-place raised-cosine ATTACK over the first [param n_samples] only. Applied AFTER the decay
## envelope (which starts at full amplitude on sample 0), so a struck note ramps up instead of
## stepping.
func _attack_cos(buf: PackedFloat32Array, n_samples: int) -> void:
	var n: int = mini(n_samples, buf.size())
	for i in n:
		var t: float = float(i) / float(n)
		buf[i] *= 0.5 - 0.5 * cos(PI * t)


## Sum `seg` into `master` starting at sample `at`. Out-of-range samples of `seg` are ignored
## (lets a note's tail run past the master's own end safely).
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

## The four-section vamp: i - VI - iv - V in E natural minor, four bars each. It never settles
## -- the V (B major) at the end pulls straight back into the i at the loop point, which is what
## makes a battle bed feel unresolved rather than restful.
## Each entry: the bass root (MIDI), the pad triad (MIDI), and the ostinato's own 4 eighth-note
## degrees for that section.
const SECTIONS: Array = [
	{ "bass": 28.0, "triad": [52.0, 55.0, 59.0], "figure": [64.0, 71.0, 64.0, 67.0] },  # Em : E3 G3 B3
	{ "bass": 24.0, "triad": [48.0, 52.0, 55.0], "figure": [60.0, 67.0, 60.0, 64.0] },  # C  : C3 E3 G3
	{ "bass": 21.0, "triad": [57.0, 60.0, 64.0], "figure": [69.0, 64.0, 69.0, 72.0] },  # Am : A3 C4 E4
	{ "bass": 23.0, "triad": [47.0, 51.0, 54.0], "figure": [71.0, 66.0, 71.0, 74.0] },  # B  : B2 D#3 F#3
]
const BARS_PER_SECTION: int = 4


## Assemble the whole 38.4s composite. Loop-safety (the crossfade), the headroom check and
## level (peak normalization) are applied by the caller afterward.
func _compose() -> PackedFloat32Array:
	var total_n := int(LOOP_SECONDS * SR)
	var out := PackedFloat32Array()
	out.resize(total_n)

	_add(out, _make_drone(LOOP_SECONDS), 0)
	_add_pad_sections(out)
	_add_pulse(out)
	_add_ostinato(out)
	_add_tension_stabs(out)

	return out


## Continuous low E1 drone (41.20 Hz): two barely-detuned sines for a slow analog beat, under a
## slow amplitude LFO so it breathes. An octave BELOW the menu theme's D2 drone, so even the
## sustained layer the two beds share does not sit in the same register.
func _make_drone(dur: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var root := _midi(28.0)         # E1
	var detuned := root * 1.0030    # a few cents sharp -- slow beating, not a chorus warble
	var phase_a := 0.0
	var phase_b := 0.0
	var inc_a := root / SR
	var inc_b := detuned / SR
	var lfo_period := LOOP_SECONDS / 2.0   # two breaths per loop -- closes evenly on the seam
	for i in n:
		var t := float(i) / SR
		var lfo: float = 0.75 + 0.25 * sin(TAU * t / lfo_period)
		var s: float = (sin(TAU * phase_a) + sin(TAU * phase_b)) * 0.5
		buf[i] = s * DRONE_AMP * lfo
		phase_a += inc_a
		if phase_a >= 1.0:
			phase_a -= 1.0
		phase_b += inc_b
		if phase_b >= 1.0:
			phase_b -= 1.0
	# Only the very start needs a fade-in guard (silence before playback begins); the loop seam
	# is handled by the composite crossfade, not by ducking this layer to zero at `dur`.
	_fade(buf, _ms(400), 0)
	return buf


## The harmonic bed: one sustained triad per section (see [constant SECTIONS]), each swelled in
## and out with a raised-cosine so the chord changes read as a push rather than a cut.
func _add_pad_sections(out: PackedFloat32Array) -> void:
	var span: float = BAR * float(BARS_PER_SECTION)
	for s in SECTIONS.size():
		var section: Dictionary = SECTIONS[s]
		var start: float = float(s) * span
		for m in (section["triad"] as Array):
			var voice := _osc(_midi(float(m)), span, PAD_AMP)
			# Swell over ~1 bar at each end, so three simultaneous voices never attack or
			# release as one hard edge.
			_fade(voice, _ms(BAR * 1000.0), _ms(BAR * 1000.0))
			_add(out, voice, int(start * SR))


## THE HEARTBEAT: a low sine "kick" on every eighth note, alternating the section's bass root
## and its octave so the pulse has a slight lift on the off-beats. Band-limited by construction
## -- it is one sine under a fast exponential decay, opened with a raised-cosine attack, so it
## thumps without any of the broadband click a real transient would bring.
func _add_pulse(out: PackedFloat32Array) -> void:
	var eighth: float = BEAT * 0.5
	var count: int = int(LOOP_SECONDS / eighth)
	for i in count:
		var t: float = float(i) * eighth
		var section: Dictionary = SECTIONS[_section_index(t)]
		var root: float = float(section["bass"])
		# Downbeats sit on the root; off-beats an octave up and quieter, which is what turns a
		# flat metronome into a march.
		var on_beat: bool = i % 2 == 0
		var midi: float = root if on_beat else root + 12.0
		var amp: float = PULSE_AMP if on_beat else PULSE_AMP * 0.45
		_add(out, _pulse(_midi(midi), amp, eighth * 0.9), int(t * SR))


## One heartbeat hit: a single sine under a fast exponential decay.
func _pulse(freq: float, amp: float, dur: float) -> PackedFloat32Array:
	var buf := _osc(freq, dur, amp)
	_decay(buf, 0.11)
	_attack_cos(buf, _ms(ATTACK_MS))
	_fade(buf, 0, _ms(RELEASE_MS))
	return buf


## THE OSTINATO: a driving eighth-note figure, four degrees per section (see [constant
## SECTIONS]) cycled across that section's four bars. This is the line that carries the cue --
## the menu theme has nothing like it.
func _add_ostinato(out: PackedFloat32Array) -> void:
	var eighth: float = BEAT * 0.5
	var count: int = int(LOOP_SECONDS / eighth)
	for i in count:
		var t: float = float(i) * eighth
		var section: Dictionary = SECTIONS[_section_index(t)]
		var figure: Array = section["figure"]
		var midi: float = float(figure[i % figure.size()])
		# Accent the first eighth of each beat so the figure has an internal groove instead of
		# reading as a flat run of equal notes.
		var accent: float = 1.0 if i % 2 == 0 else 0.7
		_add(out, _pluck(_midi(midi), OSTINATO_AMP * accent, eighth * 1.6), int(t * SR))


## One ostinato note: a sine fundamental plus one quiet octave partial under a shared
## exponential decay, opened with a raised-cosine attack and closed with a matching release.
## Attack order matters -- _decay starts at full amplitude on sample 0, so the attack has to be
## applied on top of it, not before it.
func _pluck(freq: float, amp: float, dur: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(dur * SR))
	_add(buf, _osc(freq, dur, amp), 0)
	_add(buf, _osc(freq * 2.0, dur, amp * H2), 0)
	_decay(buf, 0.22)
	_attack_cos(buf, _ms(ATTACK_MS))
	_fade(buf, 0, _ms(RELEASE_MS))
	return buf


## TENSION STABS: on the last beat of each section, a high two-note dyad a MINOR SECOND apart.
## Two sines a semitone apart beat audibly against each other -- the cheapest honest way to
## make a band-limited bed sound anxious without reaching for a noisy/aliasing timbre. Placed
## on the section seams so each chord change arrives with a shove.
func _add_tension_stabs(out: PackedFloat32Array) -> void:
	var span: float = BAR * float(BARS_PER_SECTION)
	for s in SECTIONS.size():
		# Land on the final beat of the section, with a deterministic per-section nudge so the
		# four stabs are not metronomically identical.
		var jitter: float = _rng.randf_range(-0.05, 0.05)
		var t: float = float(s + 1) * span - BEAT + jitter
		if t <= 0.0 or t >= LOOP_SECONDS - 1.5:
			continue
		var root: float = float((SECTIONS[s]["triad"] as Array)[2]) + 12.0
		_add(out, _pluck(_midi(root), STAB_AMP, 1.4), int(t * SR))
		_add(out, _pluck(_midi(root + 1.0), STAB_AMP * 0.8, 1.4), int(t * SR))


## Which of the four sections the time [param t] falls in. Wrapped so a note whose start time
## rounds a hair past the end still resolves.
func _section_index(t: float) -> int:
	var span: float = BAR * float(BARS_PER_SECTION)
	return clampi(int(t / span), 0, SECTIONS.size() - 1)


# =====================================================================
#  Loop safety + level
# =====================================================================

## Crossfade the tail into a copy of the head, IN PLACE, so the buffer's own end already
## resembles its own start by the time LOOP_FORWARD wraps loop_end back to sample 0. The
## rhythmic voices already close on the grid; this is for the drone and the pad, whose
## frequencies do not divide evenly into LOOP_SECONDS.
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


## Measure the composite BEFORE normalization and report it. Returns the true peak and prints a
## clip count that must be 0. It has to run BEFORE [method _normalize_to_peak]: normalization
## scales the whole buffer down, so a layer summing past +/-1.0 would look perfectly clean
## afterwards even though the mix that produced it was over budget.
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


## Scale the whole buffer so its absolute peak lands exactly on [param target] (a no-op if the
## buffer is silent). Normalizing to a MEASURED peak, rather than hand-tuning each layer to add
## up correctly, is what makes the "-16 dBFS peak" target exact regardless of how they sum.
func _normalize_to_peak(buf: PackedFloat32Array, target: float) -> void:
	var peak := 0.0
	for s in buf:
		peak = max(peak, absf(s))
	if peak <= 0.0001:
		return
	var scale := target / peak
	for i in buf.size():
		buf[i] *= scale
