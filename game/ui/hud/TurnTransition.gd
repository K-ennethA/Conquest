extends CanvasLayer

class_name TurnTransition

## Full-screen cinematic turn-transition wipe.
##
## A brief fade-to-black with the incoming player's name centred, framed in the
## Conquest amber theme (a thin amber rule + the player's colour accent under the
## text) so it reads as part of the game rather than a generic black screen.
##
## Lives on a high CanvasLayer so it draws above every HUD panel. Starts hidden
## and never blocks board input while idle -- the covering Control only switches
## its mouse_filter to STOP while the overlay is actually opaque, so a stray click
## during the wipe is swallowed instead of reaching the board.
##
## Timing (base, before Battle-Speed scaling). The ALLY (human) wipe is the full
## cinematic: fade IN ~0.25s, hold ~0.5s, fade OUT ~0.35s -- ~1.1s total. The ENEMY
## (AI) wipe is a deliberately lighter beat so the bot phase doesn't feel heavy
## every round: fade IN ~0.18s, hold ~0.25s, fade OUT ~0.25s -- ~0.68s total. Both
## sides DO play, so each turn hand-off reads clearly. Honors GameSettings: if
## animations are OFF the wipe is skipped entirely (no dead time); otherwise every
## duration is scaled by GameSettings.scaled_time() so Battle Speed also drives the
## transition. When GameSettings is absent (headless) it behaves as animations-on
## at 1x.
##
## Ally vs enemy: the wipe plays for BOTH turns; the AI side just uses the shorter
## timings above and an "ENEMY TURN" label. A new transition interrupts any
## in-flight one.

# --- Base timing (seconds, pre-scale) --------------------------------------
# Ally (human) side -- the full cinematic beat.
const FADE_IN := 0.25
const HOLD := 0.5
const FADE_OUT := 0.35
# Enemy (AI) side -- a quicker, lighter beat so the bot phase isn't heavy.
const ENEMY_FADE_IN := 0.18
const ENEMY_HOLD := 0.25
const ENEMY_FADE_OUT := 0.25

# High layer so the wipe covers the board and every HUD panel.
const OVERLAY_LAYER := 128

var _overlay: Control = null
var _fade: ColorRect = null
var _turn_label: Label = null
var _accent: ColorRect = null
var _tween: Tween = null
# The turn system we're currently listening to for turn_started (re-wired on switch).
var _watched_ts = null
# The last announced acting SIDE: -1 unknown/unset, 0 ally, 1 enemy. The big wipe
# only fires when the resolved side actually CHANGES, so a run of same-side unit
# turns (Speed mode fires turn_started per unit) collapses to a single wipe at the
# side transition. Reset to -1 on (re)wire so a fresh game re-announces turn one.
var _last_side: int = -1


func _ready() -> void:
	layer = OVERLAY_LAYER
	_build_ui()
	_set_idle()

	# Listen for turn starts from the ACTIVE TURN SYSTEM -- the reliable per-turn signal.
	# (PlayerManager.player_turn_started only fires on game start + the human's End-Turn
	# button, never for AI-driven advances, so the wipe barely ran off it.) Mirrors how
	# TurnIndicator wires to the turn system, incl. picking up an already-active one.
	if TurnSystemManager != null:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated(TurnSystemManager.get_active_turn_system())


## (Re)wire to the active turn system's turn_started when it activates or switches.
func _on_turn_system_activated(ts) -> void:
	if _watched_ts == ts:
		return
	if _watched_ts != null and is_instance_valid(_watched_ts) \
			and _watched_ts.turn_started.is_connected(_on_player_turn_started):
		_watched_ts.turn_started.disconnect(_on_player_turn_started)
	_watched_ts = ts
	# A fresh turn system (new game / mode switch) should re-announce the first turn,
	# so forget whichever side we last announced under the old system.
	_last_side = -1
	if ts != null and not ts.turn_started.is_connected(_on_player_turn_started):
		ts.turn_started.connect(_on_player_turn_started)


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	# Covering Control -- full rect. Its mouse_filter is flipped to STOP only while
	# the overlay is visible/opaque (see _set_idle / play).
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	# Black fade ground.
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.02, 0.015, 0.01, 1.0)  # near-black, faintly warm
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fade)

	# Centred content column.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	# Big turn label.
	_turn_label = Label.new()
	_turn_label.name = "TurnLabel"
	_turn_label.text = "YOUR TURN"
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_font_size_override("font_size", 54)
	_turn_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_turn_label.add_theme_color_override("font_outline_color", ConquestTheme.BROWN_DK)
	_turn_label.add_theme_constant_override("outline_size", 8)
	_turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_turn_label)

	# Thin amber rule / player-colour accent under the text.
	_accent = ColorRect.new()
	_accent.name = "Accent"
	_accent.color = ConquestTheme.AMBER
	_accent.custom_minimum_size = Vector2(220, 3)
	_accent.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_accent)


# --- Idle / visibility helpers ---------------------------------------------

func _set_idle() -> void:
	## Fully hidden and click-through -- the resting state between transitions.
	_overlay.modulate.a = 0.0
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _set_blocking(blocking: bool) -> void:
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE


func is_playing() -> bool:
	return _overlay != null and _overlay.visible


## True while the overlay is on screen -- lets UILayoutManager treat the whole
## viewport as "over UI" so board/camera input stays suppressed during the wipe.
func is_blocking_input() -> bool:
	return is_playing()


# --- Duration scaling (null-safe GameSettings) ------------------------------

func _animations_on() -> bool:
	if typeof(GameSettings) == TYPE_OBJECT:
		return GameSettings.animations_on()
	return true  # headless / absent -> behave as animations-on


func _scaled(base_seconds: float) -> float:
	if typeof(GameSettings) == TYPE_OBJECT:
		var t: float = GameSettings.scaled_time(base_seconds)
		# scaled_time returns 0 when animations are off; we already gate on that,
		# but clamp to a small floor so a zero never stalls the tween chain.
		return maxf(t, 0.01)
	return base_seconds


# --- Playback ---------------------------------------------------------------

func _on_player_turn_started(player: Player) -> void:
	# The big wipe should announce a SIDE change (ally phase <-> enemy phase), NOT
	# every unit hand-off. In Speed mode turn_started fires once PER UNIT (dozens of
	# times within one side), so gating on the acting side collapses that run to a
	# single wipe at the transition. In Traditional mode the side genuinely alternates
	# every player-phase, so the gate still plays a wipe each phase (ally->enemy->...).
	var side: int = _side_of(player)
	# Play only when the side actually changed (or we've never announced one yet).
	if side != _last_side:
		play(player)
	# Always remember the current side so a following same-side turn stays quiet.
	_last_side = side


## Resolve the acting SIDE of [param arg]: -1 unknown, 0 ally, 1 enemy.
## Defensive: the signal passes a Player, but tolerate a null or a Unit that
## exposes get_owner_player() by resolving to the owning Player first.
func _side_of(arg) -> int:
	var player = arg
	if player != null and player.has_method("get_owner_player"):
		player = player.get_owner_player()
	if player == null:
		return -1
	return 1 if player.is_ai else 0


## Play the wipe for [param player]. Interrupts any in-flight transition.
func play(player: Player) -> void:
	# A disabled-animations run skips the wipe outright (no dead time).
	if not _animations_on():
		_set_idle()
		return

	# Kill any in-flight tween so a rapid re-trigger replaces it cleanly.
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

	_apply_player(player)

	# Enemy (AI) turns get the quicker, lighter beat; ally (human) turns the full one.
	var is_enemy: bool = player != null and player.is_ai
	var fade_in: float = ENEMY_FADE_IN if is_enemy else FADE_IN
	var hold: float = ENEMY_HOLD if is_enemy else HOLD
	var fade_out: float = ENEMY_FADE_OUT if is_enemy else FADE_OUT

	_overlay.visible = true
	_overlay.modulate.a = 0.0
	_set_blocking(true)

	_tween = create_tween()
	_tween.tween_property(_overlay, "modulate:a", 1.0, _scaled(fade_in))
	_tween.tween_interval(_scaled(hold))
	_tween.tween_property(_overlay, "modulate:a", 0.0, _scaled(fade_out))
	_tween.tween_callback(_set_idle)


func _apply_player(player: Player) -> void:
	if player != null:
		# Ally/enemy framing reads better than "Player 1/2" in single-player.
		_turn_label.text = "ENEMY TURN" if player.is_ai else "YOUR TURN"
		# Accent picks up the player's team colour (kept legible), falling back to
		# amber when there isn't one.
		var col: Color = player.get_team_color()
		if col.a <= 0.0:
			col = ConquestTheme.AMBER
		else:
			col = col.lerp(ConquestTheme.CREAM, 0.15)
			col.a = 1.0
		_accent.color = col
	else:
		_turn_label.text = "NEXT TURN"
		_accent.color = ConquestTheme.AMBER
