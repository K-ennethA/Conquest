extends Control

class_name TurnTimer

## Per-unit move clock readout for Speed First mode -- and, ONLINE, the readout of the host's
## turn clock ([NetTurnClock]) for every mode.
##
## A big remaining-seconds chip that appears only while a HUMAN unit's move clock is
## armed (see [SpeedFirstTurnSystem]). The turn system is NOT in the scene tree, so it
## cannot run a countdown itself -- IT owns the arm/disarm state and THIS in-tree node
## drives the actual per-frame countdown, updates the readout, and calls back into
## [method SpeedFirstTurnSystem.expire_turn_timer] the instant it hits zero (which
## force-ends the turn exactly like the End Turn button).
##
## Drawn as a grove chip (notched navy plate, gold filigree) with the seconds in big Cinzel
## numerals. Visual bands: calm gold (>10s) -> warning-gold pulse (5-10s) -> danger-red
## pulse + urgency with a soft per-second tick (<=5s); the band colours the numerals and the
## chip's edge. Pulse honours GameSettings animations/battle-speed.
##
## NETWORK MODE (a live online match): the chip follows [signal NetSession.turn_clock_changed]
## instead -- the HOST's deadline, shown to BOTH seats (a caption says whose clock it is:
## YOUR TURN / OPPONENT) -- and never expires anything itself: at zero it just reads 0 until
## the host's timeout arrives ("TIME'S UP" flashes on [signal NetSession.turn_timed_out]). The
## per-second tick plays only on the local seat's own clock. The local Speed First clock never
## arms online (SpeedFirstTurnSystem), so the two never fight over the chip.

# Band thresholds (seconds remaining).
const BAND_AMBER_AT := 10.0   # <= this: start the warning pulse
const BAND_URGENT_AT := 5.0   # <= this: red pulse + per-second tick

# Colours from the navy + gold ConquestTheme tokens.
const COLOR_CALM_BG := ConquestTheme.PANEL                 # chip fill, calm
const COLOR_URGENT_BG := Color(0.36, 0.1, 0.12)            # chip fill, urgent (ember-dark)
const COLOR_TEXT := ConquestTheme.GOLD_LITE                # numerals, calm
const COLOR_FRAME := ConquestTheme.GOLD_DK                 # chip edge, calm
const COLOR_WARN := ConquestTheme.WARNING                  # numerals / edge, 5-10s
const COLOR_URGENT := ConquestTheme.DANGER                 # numerals / edge, <=5s

## Quiet per-second tick in the urgency band -- reuses the shared UI-click SFX at a low
## volume so no new audio asset is needed.
const TICK_SFX := &"sfx_ui_click"
const TICK_VOLUME_DB := -8.0

var turn_system: SpeedFirstTurnSystem = null
## The network session whose turn clock this chip shows (default: the NetSession autoload;
## tests inject one before adding the chip).
var session: Node = null

const CAPTION_MINE := "YOUR TURN"
const CAPTION_THEIRS := "OPPONENT"
const CAPTION_TIMEOUT := "TIME'S UP"
## How long the TIME'S UP caption holds (ms).
const TIMEOUT_FLASH_MS := 1600

# Network mode (see class docs).
var _net_mode: bool = false
var _net_mine: bool = false
var _flash_until: int = 0
var _caption: Label = null

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
var _style: OrnateStyleBox = null
## The band last painted (0 calm, 1 warning, 2 urgent), so the chip is only restyled on a
## band change rather than every frame.
var _band: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(120, 56)
	_build_ui()
	visible = false
	set_process(false)

	_wire_session()

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
	_style = ConquestTheme.chip_box(COLOR_FRAME, 0.95)
	_style.border_width = 2.0
	_style.corner = 10.0
	_style.ornament = OrnateStyleBox.Ornament.CLASP
	_style.ornament_color = Color(ConquestTheme.GOLD, 0.9)
	_style.ornament_size = 3.0
	_panel.add_theme_stylebox_override("panel", _style)
	# Self-styled: the HUD-wide ConquestTheme.apply_to() sweep must not swap the band chip
	# for the plain card frame.
	ConquestTheme.keep_style(_panel)
	add_child(_panel)

	_label = Label.new()
	_label.name = "TimerLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_override("font", MenuTheme.display_font(2))
	_label.add_theme_font_size_override("font_size", ConquestTheme.FS_BIG_NUMBER)
	_label.add_theme_color_override("font_color", COLOR_TEXT)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	ConquestTheme.keep_style(_label)
	add_child(_label)

	# Whose clock (network mode only): a small caps line under the numerals.
	_caption = Label.new()
	_caption.name = "TimerCaption"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.offset_bottom = -4
	_caption.add_theme_font_size_override("font_size", 12)
	_caption.add_theme_color_override("font_color", ConquestTheme.GOLD)
	ConquestTheme.keep_style(_caption)
	_caption.visible = false
	add_child(_caption)

# --- Network turn clock -----------------------------------------------------

func _wire_session() -> void:
	if session == null and is_inside_tree():
		session = get_node_or_null("/root/NetSession")
	if session == null:
		return
	if session.has_signal(&"turn_clock_changed") and not session.is_connected(&"turn_clock_changed", _on_net_clock):
		session.connect(&"turn_clock_changed", _on_net_clock)
	if session.has_signal(&"turn_timed_out") and not session.is_connected(&"turn_timed_out", _on_net_timed_out):
		session.connect(&"turn_timed_out", _on_net_timed_out)
	# Mounted mid-match: show the clock that is already running.
	if session.has_method("turn_clock"):
		var live: Dictionary = session.turn_clock()
		if not live.is_empty():
			_on_net_clock(live)

func _exit_tree() -> void:
	if session != null and is_instance_valid(session):
		if session.has_signal(&"turn_clock_changed") and session.is_connected(&"turn_clock_changed", _on_net_clock):
			session.disconnect(&"turn_clock_changed", _on_net_clock)
		if session.has_signal(&"turn_timed_out") and session.is_connected(&"turn_timed_out", _on_net_timed_out):
			session.disconnect(&"turn_timed_out", _on_net_timed_out)

func _local_slot() -> int:
	return int(session.local_slot()) if session != null and session.has_method("local_slot") else -1

## The host (re)opened a timed turn -- or stopped the clock ({}).
func _on_net_clock(clock: Dictionary) -> void:
	if clock.is_empty() or int(clock.get("slot", -1)) < 0:
		if _net_mode:
			_net_mode = false
			_caption.visible = false
			_stop_and_hide()
		return
	_net_mode = true
	_net_mine = int(clock.get("slot", -1)) == _local_slot()
	_armed_unit = null
	_remaining = maxf(0.0, float(clock.get("remaining_ms", 0)) / 1000.0)
	_running = true
	_pulse_t = 0.0
	_last_tick_whole = int(ceil(_remaining))
	_last_shown = -1
	_band = -1
	custom_minimum_size = Vector2(140, 70)
	_label.offset_bottom = -14
	_caption.visible = true
	if Time.get_ticks_msec() >= _flash_until:
		_caption.text = CAPTION_MINE if _net_mine else CAPTION_THEIRS
	modulate = Color(1, 1, 1, 1)
	visible = true
	set_process(true)
	_refresh_visual()

## A host timeout was applied: flash TIME'S UP (the next clock keeps the caption until it ends).
func _on_net_timed_out(_slot: int, _action: Dictionary, _strikes: int) -> void:
	_flash_until = Time.get_ticks_msec() + TIMEOUT_FLASH_MS
	if _caption != null:
		_caption.text = CAPTION_TIMEOUT

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
		# Non-speed system -> no LOCAL clock for this HUD (the network clock may still run).
		turn_system = null
		if not _net_mode:
			_stop_and_hide()

func _on_timer_armed(unit: Unit, seconds: float) -> void:
	if _net_mode:
		return  # online the host's clock owns the chip
	_armed_unit = unit
	_remaining = maxf(0.0, seconds)
	_running = true
	_pulse_t = 0.0
	_last_tick_whole = int(ceil(_remaining))
	_last_shown = -1
	_band = -1
	modulate = Color(1, 1, 1, 1)
	visible = true
	set_process(true)
	_refresh_visual()

func _on_timer_disarmed() -> void:
	if _net_mode:
		return
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
	if _net_mode:
		_process_net(delta)
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

## Network mode: mirror the session's deadline (no drift, no local expiry -- at zero the chip
## holds 0 until the host's timeout lands).
func _process_net(delta: float) -> void:
	if session != null and session.has_method("turn_clock_remaining_ms"):
		var ms: int = int(session.turn_clock_remaining_ms())
		_remaining = maxf(0.0, float(ms) / 1000.0) if ms >= 0 else maxf(0.0, _remaining - delta)
	else:
		_remaining = maxf(0.0, _remaining - delta)
	if _flash_until > 0 and Time.get_ticks_msec() >= _flash_until:
		_flash_until = 0
		_caption.text = CAPTION_MINE if _net_mine else CAPTION_THEIRS
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
			_label.text = NetTurnClock.format_ms(whole * 1000) if _net_mode and whole >= 60 else str(whole)

	var urgent: bool = _remaining <= BAND_URGENT_AT
	var pulsing: bool = _remaining <= BAND_AMBER_AT

	var band: int = 2 if urgent else (1 if pulsing else 0)
	if _style and band != _band:
		_band = band
		var fill: Color = COLOR_URGENT_BG if urgent else COLOR_CALM_BG
		var edge: Color = COLOR_URGENT if urgent else (COLOR_WARN if pulsing else COLOR_FRAME)
		_style.bg_color = Color(fill.lightened(0.05), 0.95)
		_style.bg_color_end = Color(fill.darkened(0.2), 0.95)
		_style.border_color = edge
		if _panel:
			_panel.queue_redraw()
		if _label:
			_label.add_theme_color_override("font_color",
					COLOR_URGENT if urgent else (COLOR_WARN if pulsing else COLOR_TEXT))

	# Pulse via node alpha so the whole chip breathes. Gated on the animations setting
	# (off -> solid, most readable). Urgency pulses deeper.
	if pulsing and _animations_on():
		var depth: float = 0.45 if urgent else 0.28
		var a: float = 1.0 - depth * (0.5 - 0.5 * cos(_pulse_t * TAU))
		modulate = Color(1, 1, 1, a)
	else:
		modulate = Color(1, 1, 1, 1)

	# Soft per-second tick inside the urgency band.
	if urgent and _remaining > 0.0 and whole != _last_tick_whole and (not _net_mode or _net_mine):
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

## True while the chip shows the ONLINE host clock.
func is_net_mode() -> bool:
	return _net_mode

## True when the shown network clock is the local seat's.
func is_own_clock() -> bool:
	return _net_mode and _net_mine

## The numerals as drawn ("20", "1:35").
func readout_text() -> String:
	return _label.text if _label != null else ""

## The caption line (YOUR TURN / OPPONENT / TIME'S UP), "" outside network mode.
func caption_text() -> String:
	return _caption.text if _caption != null and _caption.visible else ""

## The urgency band drawn (0 calm, 1 warning, 2 urgent -- under [constant BAND_URGENT_AT]).
func band() -> int:
	return _band
