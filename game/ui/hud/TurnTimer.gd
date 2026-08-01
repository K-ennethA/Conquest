extends Control

class_name TurnTimer

## Per-unit move clock readout for Speed First mode.
##
## A big remaining-seconds chip that appears only while a HUMAN unit's move clock is
## armed (see [SpeedFirstTurnSystem]). The turn system is NOT in the scene tree, so it
## cannot run a countdown itself -- IT owns the arm/disarm state and THIS in-tree node
## drives the actual per-frame countdown, updates the readout, and calls back into
## [method SpeedFirstTurnSystem.expire_turn_timer] the instant it hits zero (which
## force-ends the turn exactly like the End Turn button).
##
## Visual bands: calm amber (>10s) -> amber pulse (5-10s) -> red pulse + urgency with a
## soft per-second tick (<=5s). Pulse honours GameSettings animations/battle-speed.

# Band thresholds (seconds remaining).
const BAND_AMBER_AT := 10.0   # <= this: start the amber pulse
const BAND_URGENT_AT := 5.0   # <= this: red pulse + per-second tick

# Colours pulled from the warm ConquestTheme palette (+ a warm red for urgency).
const COLOR_CALM_BG := Color(0.90, 0.65, 0.29)     # AMBER
const COLOR_URGENT_BG := Color(0.85, 0.29, 0.18)   # warm ember red
const COLOR_TEXT := Color(0.99, 0.94, 0.84)        # CREAM
const COLOR_FRAME := Color(0.22, 0.13, 0.06)       # BROWN_DK

## Quiet per-second tick in the urgency band -- reuses the shared UI-click SFX at a low
## volume so no new audio asset is needed.
const TICK_SFX := &"sfx_ui_click"
const TICK_VOLUME_DB := -8.0

var turn_system: SpeedFirstTurnSystem = null

# Countdown state.
var _running: bool = false
var _remaining: float = 0.0
var _armed_unit: Unit = null
var _pulse_t: float = 0.0
## Whole-second value last ticked, so the urgency tick fires once per second, not per frame.
var _last_tick_whole: int = -1
## Displayed integer, so the label text is only rebuilt when it actually changes.
var _last_shown: int = -1

# Built-in-code UI (kept out of a .tscn so mounting stays a pure code path).
var _panel: Panel = null
var _label: Label = null
var _style: StyleBoxFlat = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(120, 56)
	_build_ui()
	visible = false
	set_process(false)

	# Track the active turn system exactly like TurnQueue does, and hook it now if one
	# is already active (this HUD can be mounted after the match starts).
	if TurnSystemManager:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated(TurnSystemManager.get_active_turn_system())

func _build_ui() -> void:
	_panel = Panel.new()
	_panel.name = "TimerPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style = StyleBoxFlat.new()
	_style.bg_color = COLOR_CALM_BG
	_style.border_color = COLOR_FRAME
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", _style)
	add_child(_panel)

	_label = Label.new()
	_label.name = "TimerLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", COLOR_TEXT)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

# --- Turn-system wiring -----------------------------------------------------

func _on_turn_system_activated(system: TurnSystemBase) -> void:
	# Disconnect any previous system's clock signals first so we never double-fire.
	if turn_system != null and is_instance_valid(turn_system):
		if turn_system.turn_timer_armed.is_connected(_on_timer_armed):
			turn_system.turn_timer_armed.disconnect(_on_timer_armed)
		if turn_system.turn_timer_disarmed.is_connected(_on_timer_disarmed):
			turn_system.turn_timer_disarmed.disconnect(_on_timer_disarmed)

	if system is SpeedFirstTurnSystem:
		turn_system = system as SpeedFirstTurnSystem
		if not turn_system.turn_timer_armed.is_connected(_on_timer_armed):
			turn_system.turn_timer_armed.connect(_on_timer_armed)
		if not turn_system.turn_timer_disarmed.is_connected(_on_timer_disarmed):
			turn_system.turn_timer_disarmed.connect(_on_timer_disarmed)
		# Re-sync in case a clock is already armed (mounted mid-turn).
		if turn_system.turn_timer_active and turn_system.turn_timer_unit != null:
			_on_timer_armed(turn_system.turn_timer_unit, turn_system.turn_timer_seconds)
	else:
		# Non-speed system -> no clock for this HUD.
		turn_system = null
		_stop_and_hide()

func _on_timer_armed(unit: Unit, seconds: float) -> void:
	_armed_unit = unit
	_remaining = maxf(0.0, seconds)
	_running = true
	_pulse_t = 0.0
	_last_tick_whole = int(ceil(_remaining))
	_last_shown = -1
	modulate = Color(1, 1, 1, 1)
	visible = true
	set_process(true)
	_refresh_visual()

func _on_timer_disarmed() -> void:
	_stop_and_hide()

func _stop_and_hide() -> void:
	_running = false
	_armed_unit = null
	set_process(false)
	visible = false
	modulate = Color(1, 1, 1, 1)

# --- Countdown --------------------------------------------------------------

func _process(delta: float) -> void:
	if not _running:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_remaining = 0.0
		_refresh_visual()
		# Fire the expiry ONCE: stop counting first so a same-frame re-entry can't
		# re-trigger, then hand off to the turn system's guarded force-end.
		_running = false
		set_process(false)
		var unit := _armed_unit
		if turn_system != null and is_instance_valid(turn_system) and unit != null:
			turn_system.expire_turn_timer(unit)
		# The system's expire_turn_timer disarms the clock, which hides us via
		# _on_timer_disarmed. If it was a stale no-op, hide defensively anyway.
		if _running == false and visible:
			_stop_and_hide()
		return

	_pulse_t += delta * _pulse_speed()
	_refresh_visual()

## Rebuild the readout + colour for the current remaining time. Cheap: the label text is
## only rewritten when its integer changes, and the stylebox colour is set every call but
## from a constant (no allocation).
func _refresh_visual() -> void:
	var whole: int = int(ceil(_remaining))
	if whole != _last_shown:
		_last_shown = whole
		if _label:
			_label.text = str(whole)

	var urgent: bool = _remaining <= BAND_URGENT_AT
	var pulsing: bool = _remaining <= BAND_AMBER_AT

	if _style:
		_style.bg_color = COLOR_URGENT_BG if urgent else COLOR_CALM_BG

	# Pulse via node alpha so the whole chip breathes. Gated on the animations setting
	# (off -> solid, most readable). Urgency pulses deeper.
	if pulsing and _animations_on():
		var depth: float = 0.45 if urgent else 0.28
		var a: float = 1.0 - depth * (0.5 - 0.5 * cos(_pulse_t * TAU))
		modulate = Color(1, 1, 1, a)
	else:
		modulate = Color(1, 1, 1, 1)

	# Soft per-second tick inside the urgency band.
	if urgent and _remaining > 0.0 and whole != _last_tick_whole:
		_last_tick_whole = whole
		_play_tick()

## Pulse cycles per second, scaled by battle speed so "Fast" feels more urgent. Faster in
## the urgency band. Null-safe read of GameSettings.
func _pulse_speed() -> float:
	var base: float = 2.0 if _remaining <= BAND_URGENT_AT else 1.2
	var speed: float = 1.0
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null and "battle_speed" in GameSettings:
		speed = clampf(float(GameSettings.battle_speed), 0.5, 3.0)
	return base * speed

func _animations_on() -> bool:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null and GameSettings.has_method("animations_on"):
		return bool(GameSettings.animations_on())
	return true

func _play_tick() -> void:
	if typeof(AudioManager) == TYPE_OBJECT and AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx(TICK_SFX, TICK_VOLUME_DB)

# --- Test / query helpers ---------------------------------------------------

## True while the countdown is live (armed + running).
func is_running() -> bool:
	return _running

## Seconds currently remaining on the readout (0 when idle).
func seconds_left() -> float:
	return _remaining if _running else 0.0
