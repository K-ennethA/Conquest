extends GutTest

## AudioManager.volume_to_db -- the ONE place GameSettings' linear 0..1 volumes
## become decibels.
##
## It is a static, side-effect-free function precisely so this suite can pin it
## without an audio device, a scene tree or any autoload state: every assertion
## below is a pure call. The behaviour that matters is the SILENCE edge --
## `linear_to_db(0.0)` is -INF, and AudioManager SUMS these terms with the
## library's base level and the developer trims, so a single -INF would poison
## every music/SFX level in the game. Zero has to land on a finite floor.

const EPSILON := 0.01


func test_unity_is_unchanged() -> void:
	assert_almost_eq(AudioManager.volume_to_db(1.0), 0.0, EPSILON,
		"a slider at 100% must not attenuate or boost the authored mix")


func test_half_amplitude_is_about_minus_six_db() -> void:
	assert_almost_eq(AudioManager.volume_to_db(0.5), -6.02, EPSILON,
		"halving linear amplitude is -6 dB (20*log10(0.5))")


func test_shipped_defaults_map_to_their_documented_trims() -> void:
	assert_almost_eq(AudioManager.volume_to_db(0.6), -4.44, EPSILON,
		"the default music volume (0.6) is a -4.4 dB trim")
	assert_almost_eq(AudioManager.volume_to_db(0.8), -1.94, EPSILON,
		"the default UI volume (0.8) is a -1.9 dB trim")


func test_zero_is_a_finite_silence_floor_not_negative_infinity() -> void:
	var silent: float = AudioManager.volume_to_db(0.0)
	assert_eq(silent, AudioManager.SILENT_DB,
		"a slider at 0 resolves to the SILENT_DB floor")
	assert_true(is_finite(silent),
		"the floor must be FINITE -- AudioManager adds it to other dB terms, and -INF would poison the sum")


func test_values_within_the_silence_threshold_also_floor() -> void:
	assert_eq(AudioManager.volume_to_db(AudioManager.SILENT_THRESHOLD * 0.5), AudioManager.SILENT_DB,
		"float rounding near the slider's minimum still counts as off")


func test_out_of_range_input_is_clamped_at_both_ends() -> void:
	assert_eq(AudioManager.volume_to_db(-1.0), AudioManager.SILENT_DB,
		"a negative amplitude is silence, never a math error")
	assert_almost_eq(AudioManager.volume_to_db(2.0), 0.0, EPSILON,
		"there is no boost above unity -- above-1.0 input clamps to the authored level")


func test_mapping_is_monotonic() -> void:
	var quiet: float = AudioManager.volume_to_db(0.25)
	var mid: float = AudioManager.volume_to_db(0.5)
	var loud: float = AudioManager.volume_to_db(1.0)
	assert_lt(quiet, mid, "a lower slider position is always quieter")
	assert_lt(mid, loud, "and that holds all the way to the top of the range")
