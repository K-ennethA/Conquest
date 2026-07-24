extends Control

class_name GameOverScreen

# Animated end-of-battle overlay: a full-screen VICTORY / DEFEAT card that drops
# in when a player is eliminated and the game is decided. Offers Rematch (reload
# the battle), Main Menu, and Quit.
#
# Code-built like TerrainInfoPanel / CombatForecastPanel: the .tscn is just a
# full-rect Control shell with this script attached, and _ready() builds the
# backdrop, result card, banner, and buttons, then themes them with the amber
# battle HUD look (ConquestTheme). Hidden by default; GameWorldManager decides
# the outcome and calls show_victory()/show_defeat() (or show_result()).
#
# Idempotent: once shown it ignores further calls (`_shown`), so multiple
# elimination signals arriving in the same frame never restack the reveal.
#
# Runs while the tree is paused: the whole node is PROCESS_MODE_ALWAYS and the
# reveal Tween is TWEEN_PAUSE_PROCESS, so pausing gameplay on game over does not
# freeze the animation or block the buttons.

# --- Tunables ---------------------------------------------------------------
const CARD_WIDTH := 560.0
const REVEAL_SCALE_FROM := 0.6   # banner/card starts small then pops to 1.0
const REVEAL_SLIDE_PX := 26.0    # card starts this many px high and settles down

# Banner accents: bright gold for a win, desaturated red for a loss.
const VICTORY_GOLD := Color("f5c95a")
const DEFEAT_RED := Color("c15a48")

# Outcome tags (also used by GameWorldManager for the neutral versus banner).
const OUTCOME_VICTORY := &"victory"
const OUTCOME_DEFEAT := &"defeat"

# Idempotency guard -- true once the screen has been revealed.
var _shown: bool = false

# Nodes built in _create_ui().
var _backdrop: ColorRect
var _card: PanelContainer
var _banner_label: Label
var _subtitle_label: Label
var _button_box: VBoxContainer
var _rematch_button: Button
var _menu_button: Button
var _quit_button: Button
var _reveal_tween: Tween


func _ready() -> void:
	name = "GameOverScreen"

	# Animate + accept clicks even when gameplay pauses on game over (see file note).
	process_mode = Node.PROCESS_MODE_ALWAYS

	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Swallow clicks once shown so the board underneath can't be commanded. While
	# hidden (visible = false) a Control receives no input, so this never blocks
	# the board during normal play or at boot.
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Draw above every HUD panel in the shared "UI" CanvasLayer.
	z_as_relative = false
	z_index = 4096

	_create_ui()
	visible = false


func _create_ui() -> void:
	# Dimmed backdrop covering the whole viewport; fades in with the reveal and,
	# with mouse_filter STOP, catches any click outside the card.
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.04, 0.02, 0.0, 0.72)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	# Centered result card. Anchors pinned to the viewport centre with grow BOTH
	# means it is sized to its content's minimum and centred, no CenterContainer
	# needed -- leaving its transform (scale/position) free for the pop animation.
	_card = PanelContainer.new()
	_card.name = "ResultCard"
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	# Keep the scale pivot at the card's centre as it lays out, so the pop scales
	# from the middle rather than the top-left corner.
	_card.resized.connect(_recenter_pivot)
	add_child(_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_card.add_child(vb)

	_banner_label = Label.new()
	_banner_label.name = "BannerLabel"
	_banner_label.text = "VICTORY"
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 64)
	vb.add_child(_banner_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.text = "All enemies defeated!"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 20)
	vb.add_child(_subtitle_label)

	var sep := HSeparator.new()
	vb.add_child(sep)

	_button_box = VBoxContainer.new()
	_button_box.name = "Buttons"
	_button_box.add_theme_constant_override("separation", 10)
	vb.add_child(_button_box)

	_rematch_button = _make_button("Rematch")
	_rematch_button.pressed.connect(_on_rematch_pressed)
	_button_box.add_child(_rematch_button)

	_menu_button = _make_button("Main Menu")
	_menu_button.pressed.connect(_on_main_menu_pressed)
	_button_box.add_child(_menu_button)

	_quit_button = _make_button("Quit")
	_quit_button.pressed.connect(_on_quit_pressed)
	_button_box.add_child(_quit_button)

	# Amber HUD look. apply_to strips baked font_color overrides, so the banner
	# outline / subtitle tint / per-outcome banner colour are all set AFTER it so
	# they survive.
	ConquestTheme.apply_to(self)

	# Punchy dark outline on the big banner, and a muted subtitle.
	_banner_label.add_theme_constant_override("outline_size", 8)
	_banner_label.add_theme_color_override("font_outline_color", ConquestTheme.BROWN_DK)
	_subtitle_label.add_theme_color_override("font_color", ConquestTheme.INK_SOFT)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_ALL
	return b


# --- Public API --------------------------------------------------------------

## True once the screen has been revealed (used by callers to avoid re-triggering).
func is_shown() -> bool:
	return _shown


## Reveal a win for the local human ("VICTORY", gold).
func show_victory() -> void:
	show_result(OUTCOME_VICTORY, "VICTORY", "All enemies defeated!")


## Reveal a loss for the local human ("DEFEAT", red).
func show_defeat() -> void:
	show_result(OUTCOME_DEFEAT, "DEFEAT", "Your forces have fallen.")


## Reveal the end screen with an explicit banner. Idempotent -- the first call
## wins and later calls are ignored, so repeated elimination signals never
## restack the animation. Pauses gameplay while the (pause-immune) reveal runs.
func show_result(outcome: StringName, title: String, subtitle: String) -> void:
	if _shown:
		return
	_shown = true

	_banner_label.text = title
	_subtitle_label.text = subtitle

	var accent: Color = VICTORY_GOLD if outcome == OUTCOME_VICTORY else DEFEAT_RED
	_banner_label.add_theme_color_override("font_color", accent)

	visible = true

	# Freeze gameplay. Safe because this node is PROCESS_MODE_ALWAYS and the reveal
	# tween is TWEEN_PAUSE_PROCESS, so the screen keeps animating and its buttons
	# keep working while the tree is paused.
	get_tree().paused = true

	_play_reveal_animation()
	_play_sting(outcome)

	# Give the primary action keyboard/controller focus.
	_rematch_button.grab_focus()


# --- Reveal animation --------------------------------------------------------

func _recenter_pivot() -> void:
	if _card != null:
		_card.pivot_offset = _card.size / 2.0


func _play_reveal_animation() -> void:
	_recenter_pivot()

	# Defensive: show_result is idempotent so there is normally no prior tween.
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()

	# Initial hidden pose: dim backdrop, small/transparent card lifted slightly,
	# invisible buttons.
	_backdrop.modulate.a = 0.0
	_card.modulate.a = 0.0
	_card.scale = Vector2(REVEAL_SCALE_FROM, REVEAL_SCALE_FROM)
	var rest_y: float = _card.position.y
	_card.position.y = rest_y - REVEAL_SLIDE_PX
	for child in _button_box.get_children():
		var ctl := child as Control
		if ctl != null:
			ctl.modulate.a = 0.0

	_reveal_tween = create_tween()
	# Keep animating while gameplay is paused (see show_result).
	_reveal_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_reveal_tween.set_parallel(true)

	# Backdrop dims in.
	_reveal_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.28) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Card pops: scale overshoot (TRANS_BACK) + fade + gentle slide down to rest.
	_reveal_tween.tween_property(_card, "modulate:a", 1.0, 0.26) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(_card, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(_card, "position:y", rest_y, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Buttons fade in staggered after the card has mostly landed. Total reveal
	# stays under ~0.75s so it reads snappy (reduced-motion friendly).
	var delay: float = 0.30
	for child in _button_box.get_children():
		var ctl := child as Control
		if ctl == null:
			continue
		_reveal_tween.tween_property(ctl, "modulate:a", 1.0, 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(delay)
		delay += 0.08


func _play_sting(outcome: StringName) -> void:
	# Optional audio: play a victory/defeat sting if AudioManager exposes play_sfx.
	# Unknown/unassigned events no-op inside the manager, so this is always safe.
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null or not audio.has_method("play_sfx"):
		return
	var event_name: StringName = &"sfx_victory" if outcome == OUTCOME_VICTORY else &"sfx_defeat"
	audio.play_sfx(event_name)


# --- Button handlers ---------------------------------------------------------
# Every handler unpauses the tree first: get_tree().paused persists across a
# scene change, so leaving it true would freeze the reloaded battle / the menu.

func _on_rematch_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()
