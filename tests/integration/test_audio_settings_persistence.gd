extends GutTest

## GameSettings' audio block: defaults, clamping, live notification, and the
## disk ROUND TRIP (setter -> user://*.cfg -> reload).
##
## This suite calls the real persisting setters, which is normally forbidden
## (tests/README.md rule 3) -- it is allowed here ONLY because
## `GameSettings.set_settings_path()` redirects the whole presentation block to
## [constant TEMP_SETTINGS_PATH] for the duration, which is exactly the
## path-injection API rule 4 asks for. The player's real settings.cfg is never
## opened. `before_all` redirects, `after_all` deletes the temp file, restores
## the default path and re-reads the player's real values back into memory; the
## per-test guard restores the in-memory fields even when an assertion fails.

const Guard := preload("res://tests/helpers/global_state_guard.gd")

const TEMP_SETTINGS_PATH := "user://test_audio_settings.cfg"

## Untyped on purpose: a `: RefCounted` annotation would make the static analyser reject
## _guard.set_setting() / .watch_setting() as "not found in base RefCounted".
var _guard


func before_all() -> void:
	GameSettings.set_settings_path(TEMP_SETTINGS_PATH)


func after_all() -> void:
	GameSettings.set_settings_path(GameSettings.DEFAULT_SETTINGS_PATH)
	if FileAccess.file_exists(TEMP_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SETTINGS_PATH))
	# Put the PLAYER's own persisted values back in memory, so nothing this suite
	# assigned survives into the rest of the run.
	GameSettings.reload_presentation_settings()


func before_each() -> void:
	_guard = Guard.new()
	# PINNED, not merely watched: every setter below no-ops when the value is
	# already what is being set, so a machine whose real settings happened to
	# match a test's target would silently skip the write it is asserting on.
	# set_setting() assigns the field directly (no persistence) after snapshotting.
	_guard.set_setting("master_volume", 1.0)
	_guard.set_setting("music_volume", 0.6)
	_guard.set_setting("ui_volume", 0.8)
	_guard.set_setting("speed_turn_timer_seconds", 30)
	# reload_presentation_settings() rewrites the WHOLE block, so the three
	# non-audio keys are in scope for this suite too even though it never sets them.
	_guard.watch_setting("animations_enabled")
	_guard.watch_setting("battle_speed")
	_guard.watch_setting("camera_auto_focus")


func after_each() -> void:
	_guard.restore()


# --- Defaults ---------------------------------------------------------------

func test_shipped_defaults() -> void:
	# A FRESH instance, never added to the tree: _ready (and therefore the load
	# from disk) does not run, so these are the authored defaults rather than
	# whatever this machine has saved.
	#
	# Untyped for the same reason tests/README.md keeps `var _guard` untyped: a
	# `: Node` annotation makes the static analyser reject `fresh.master_volume`
	# as "not found in base Node".
	var fresh = autofree(load("res://systems/game_settings.gd").new())
	assert_almost_eq(float(fresh.master_volume), 1.0, 0.001,
		"master ships unattenuated -- the player's system volume is the outer knob")
	assert_almost_eq(float(fresh.music_volume), 0.6, 0.001,
		"music ships below unity so the bed sits under the SFX")
	assert_almost_eq(float(fresh.ui_volume), 0.8, 0.001,
		"UI cues ship slightly trimmed")


# --- Clamping ---------------------------------------------------------------

func test_volumes_clamp_to_zero_one() -> void:
	GameSettings.set_master_volume(5.0)
	assert_almost_eq(float(GameSettings.master_volume), 1.0, 0.001,
		"there is no boost above unity")
	GameSettings.set_master_volume(-3.0)
	assert_almost_eq(float(GameSettings.master_volume), 0.0, 0.001,
		"a negative volume clamps to silence, it does not invert the signal")


# --- Live notification ------------------------------------------------------

func test_changing_a_volume_announces_it() -> void:
	GameSettings.music_volume = 0.5
	watch_signals(GameSettings)
	GameSettings.set_music_volume(0.25)
	assert_signal_emitted(GameSettings, "settings_changed",
		"AudioManager re-levels off this signal -- without it a slider is silent until the next scene")


func test_setting_the_same_volume_twice_is_a_no_op() -> void:
	GameSettings.set_ui_volume(0.45)
	watch_signals(GameSettings)
	GameSettings.set_ui_volume(0.45)
	assert_signal_not_emitted(GameSettings, "settings_changed",
		"an unchanged value must not re-save or re-notify")


# --- Round trip -------------------------------------------------------------

func test_volumes_survive_a_save_and_reload() -> void:
	GameSettings.set_master_volume(0.35)
	GameSettings.set_music_volume(0.15)
	GameSettings.set_ui_volume(0.55)

	# Scribble over the in-memory values, so a passing reload can only come from disk.
	GameSettings.master_volume = 1.0
	GameSettings.music_volume = 1.0
	GameSettings.ui_volume = 1.0

	GameSettings.reload_presentation_settings()

	assert_almost_eq(float(GameSettings.master_volume), 0.35, 0.001,
		"master volume came back off disk")
	assert_almost_eq(float(GameSettings.music_volume), 0.15, 0.001,
		"music volume came back off disk")
	assert_almost_eq(float(GameSettings.ui_volume), 0.55, 0.001,
		"UI volume came back off disk")


func test_speed_timer_snaps_and_survives_a_reload() -> void:
	# The Settings panel's stepper only offers allowed values, but the setter is
	# the guarantee: anything else snaps to the nearest of 0/15/20/30.
	GameSettings.set_speed_turn_timer_seconds(17)
	assert_eq(int(GameSettings.speed_turn_timer_seconds), 15,
		"17s snaps to the nearest allowed clock, 15s")

	GameSettings.speed_turn_timer_seconds = 30
	GameSettings.reload_presentation_settings()
	assert_eq(int(GameSettings.speed_turn_timer_seconds), 15,
		"and the snapped value is what persisted")


func test_a_saved_volume_does_not_clobber_the_other_presentation_keys() -> void:
	var animations_before: bool = bool(GameSettings.animations_enabled)
	GameSettings.set_music_volume(0.05)
	GameSettings.reload_presentation_settings()
	assert_eq(bool(GameSettings.animations_enabled), animations_before,
		"writing one key rewrites the whole section -- the others must round-trip unchanged")
