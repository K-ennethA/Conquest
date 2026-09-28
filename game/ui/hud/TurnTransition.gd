extends CanvasLayer

class_name TurnTransition

## Full-screen cinematic turn-transition wipe.
##
## A brief Fire-Emblem "PHASE" banner: the board dims to navy and a full-width
## band sweeps in with the phase title ("PLAYER PHASE" / "ENEMY PHASE", or YOUR /
## OPPONENT'S TURN online) in the acting side's team colour, framed by team-colour
## rules, with the round number underneath.
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

# Beat held BEFORE the "YOUR TURN" wipe when control passes from the AI back to the human.
# The AI's last action resolves and advances the turn synchronously, so without this the
# wipe would start on top of that final strike -- the enemy's move (and its banner) would
# land ON the player's turn. During this hold the overlay is TRANSPARENT but input-blocking:
# the player watches the last enemy action finish, then the wipe fades in. Scaled by Battle
# Speed like everything else.
const POST_ENEMY_HOLD := 1.5
## Floor (seconds) on the post-enemy hold AFTER battle-speed scaling -- even on Fast, the
## last enemy action gets a clear beat before control returns.
const POST_ENEMY_HOLD_MIN := 0.9

# High layer so the wipe covers the board and every HUD panel.
const OVERLAY_LAYER := 128

var _overlay: Control = null
var _fade: ColorRect = null
var _turn_label: Label = null
var _accent: GroveRule = null
var _band: Panel = null
var _rule_top: ColorRect = null
var _rule_bottom: ColorRect = null
var _sub_label: Label = null
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
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings.has_signal("fast_forward_changed") \
			and not GameSettings.fast_forward_changed.is_connected(_on_fast_forward_changed):
		GameSettings.fast_forward_changed.connect(_on_fast_forward_changed)

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

	# Navy dim over the whole board.
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(ConquestTheme.BG_DEEP.r, ConquestTheme.BG_DEEP.g, ConquestTheme.BG_DEEP.b, 0.72)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fade)

	# Thin team-colour rules run the full width; the heraldic phase RIBBON (swallow-
	# tailed, gold filigree, crest on top) spans the middle over them.
	_rule_top = _make_rule(-62.0)
	_rule_bottom = _make_rule(58.0)
	_band = Panel.new()
	_band.name = "Band"
	_band.anchor_left = 0.14
	_band.anchor_right = 0.86
	_band.anchor_top = 0.5
	_band.anchor_bottom = 0.5
	_band.offset_top = -80.0
	_band.offset_bottom = 80.0
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_theme_stylebox_override("panel", _band_box(ConquestTheme.GOLD))
	_overlay.add_child(_band)

	# Centred content column.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	# Big phase title.
	_turn_label = Label.new()
	_turn_label.name = "TurnLabel"
	_turn_label.text = "PLAYER PHASE"
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_font_override("font", MenuTheme.display_font(8))
	_turn_label.add_theme_font_size_override("font_size", 60)
	_turn_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_turn_label.add_theme_color_override("font_outline_color", ConquestTheme.BG_DEEP)
	_turn_label.add_theme_constant_override("outline_size", 8)
	_turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_turn_label)

	# Short gold rule / team accent under the title.
	_accent = GroveRule.new()
	_accent.name = "Accent"
	_accent.color = ConquestTheme.GOLD
	_accent.centered = true
	_accent.custom_minimum_size = Vector2(320, 12)
	_accent.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_accent)

	_sub_label = Label.new()
	_sub_label.name = "SubLabel"
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
	_sub_label.add_theme_color_override("font_color", ConquestTheme.TEXT_DIM)
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_sub_label)


## The phase ribbon: navy, swallow-tailed ends, team-colour edge, gold filigree
## and crest.
func _band_box(team: Color) -> StyleBox:
	var sb := MenuTheme.ribbon_box(ConquestTheme.PANEL, team, 46.0)
	sb.bg_color = Color(ConquestTheme.PANEL.lightened(0.1), 0.97)
	sb.bg_color_end = Color(ConquestTheme.PANEL.darkened(0.4), 0.97)
	sb.border_width = 3.0
	sb.inner_line_color = Color(ConquestTheme.GOLD, 0.55)
	sb.inner_inset = 7.0
	sb.crest = true
	sb.ornament_color = ConquestTheme.GOLD
	sb.ornament_size = 5.0
	sb.shadow_size = 18.0
	sb.shadow_color = Color(0, 0, 0, 0.55)
	return sb


func _make_rule(offset_top: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = ConquestTheme.GOLD
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = 0.5
	r.anchor_bottom = 0.5
	r.offset_top = offset_top
	r.offset_bottom = offset_top + 2.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(r)
	return r


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

# Fast-forward factor in force when the current wipe started (its durations already
# include it via scaled_time); a mid-wipe press/release rescales the running tween.
var _ff_at_start: float = 1.0

func _ff_factor() -> float:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings.has_method("fast_forward_factor"):
		return maxf(1.0, float(GameSettings.fast_forward_factor()))
	return 1.0


func _on_fast_forward_changed(_active: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.set_speed_scale(_ff_factor() / maxf(1.0, _ff_at_start))


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
		# Hand-off from the AI (enemy, side 1) back to the human (ally, side 0) gets a
		# pre-hold so the enemy's LAST action is seen before the wipe covers the board.
		var pre_hold: float = POST_ENEMY_HOLD if (_last_side == 1 and side == 0) else 0.0
		play(player, pre_hold)
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


## Play the wipe for [param player]. Interrupts any in-flight transition. [param pre_hold]
## (seconds, pre-scale) is a leading TRANSPARENT but input-blocking beat -- used on the
## AI->human hand-off so the enemy's last action is watched before the wipe fades in.
func play(player: Player, pre_hold: float = 0.0) -> void:
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

	# Overlay on and BLOCKING immediately (so the player can't act during the pre-hold),
	# but transparent -- the board + the last enemy action + its banner stay visible until
	# the wipe fades in.
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	_set_blocking(true)

	_ff_at_start = _ff_factor()
	_tween = create_tween()
	if pre_hold > 0.0:
		# Floor the scaled hold so even Fast battle speed keeps a readable beat on the
		# enemy's last action before the wipe covers the board.
		_tween.tween_interval(maxf(POST_ENEMY_HOLD_MIN, _scaled(pre_hold)))
	_tween.tween_property(_overlay, "modulate:a", 1.0, _scaled(fade_in))
	_tween.tween_interval(_scaled(hold))
	_tween.tween_property(_overlay, "modulate:a", 0.0, _scaled(fade_out))
	_tween.tween_callback(_set_idle)


func _apply_player(player: Player) -> void:
	var team: Color = ConquestTheme.GOLD
	if player != null:
		_turn_label.text = ConquestTheme.phase_title(player)
		team = ConquestTheme.team_color(player)
		_turn_label.add_theme_color_override("font_color", ConquestTheme.team_text_color(player).lerp(ConquestTheme.CREAM, 0.25))
	else:
		_turn_label.text = "NEXT TURN"
		_turn_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_accent.color = ConquestTheme.GOLD
	if _band:
		_band.add_theme_stylebox_override("panel", _band_box(team))
	if _rule_top:
		_rule_top.color = Color(team, 0.7)
		_rule_bottom.color = Color(team, 0.7)
	if _sub_label:
		var round_no := _round_number()
		_sub_label.text = "Round %d" % round_no if round_no > 0 else ""
		_sub_label.visible = round_no > 0


func _round_number() -> int:
	if _watched_ts != null and is_instance_valid(_watched_ts) and "current_turn" in _watched_ts:
		return int(_watched_ts.current_turn)
	return 0
