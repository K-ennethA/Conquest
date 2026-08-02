extends Control

class_name MainMenu

# Main menu for the tactical combat game
# Provides game mode selection (Single Player vs Versus)

@onready var single_player_button: Button = $Layout/CenterBlock/Column/MenuButtons/SinglePlayerButton
@onready var versus_button: Button = $Layout/CenterBlock/Column/MenuButtons/VersusButton
# One entry point for the whole in-game reference. The Unit, Tile and Map
# galleries are no longer separate menu items -- they are sections of
# Compendium.tscn, which also covers Statuses (and, later, Weather).
@onready var compendium_button: Button = $Layout/CenterBlock/Column/MenuButtons/CompendiumButton
# Arena is no longer a top-level sibling: it lives under Solo -> Arena Run now.
@onready var map_creator_button: Button = $Layout/CenterBlock/Column/MenuButtons/MapCreatorButton
@onready var quit_button: Button = $Layout/CenterBlock/Column/MenuButtons/QuitButton

# Progression (rank, points, achievements) -- reached through the top-right profile chip
# now, not a column entry. Collection (the cosmetic wardrobe) is nested a level further in,
# as a card on ProfileScreen -- it is no longer directly reachable from the main menu.
const PROFILE_SCENE := "res://menus/ProfileScreen.tscn"

# The code-built top-right chip badge text, and its no-autoload fallback label.
const PROFILE_MONOGRAM := "P"
const PROFILE_FALLBACK_LABEL := "PROFILE"

# --- TopBar geometry --------------------------------------------------------
# A Button is NOT a Container, so the chip's badge+label HBox (added with a
# full-rect anchor preset, the "content over a plain button" trick) contributes
# NOTHING to the button's minimum size. Left to itself the chip was only as wide
# as an empty button -- ~28px of stylebox padding -- and its content simply drew
# past the right edge, which is the "profile is cut off" report. So the chip's
# width is stated here instead of inferred, and the rank label ellipsises inside
# it rather than overflowing.
#
# The row is [gear][chip], right-aligned inside TOP_BAR_MARGIN on each side:
#   24 (margin) + 44 (gear) + 8 (separation) + 200 (chip) + 24 (margin) = 300px,
# against a 1280-wide viewport -- the row starts at x=1004 and its right edge
# lands exactly on 1256 = 1280 - 24. Nothing can reach the screen edge.
const TOP_BAR_MARGIN := 24
const TOP_BAR_SEPARATION := 8
const CHIP_WIDTH := 200.0
const CHIP_HEIGHT := 44.0        # touch rule: >= 44px tall
const CHIP_PADDING := 12.0       # inset of the chip's content from each of its own edges
const CHIP_BADGE_SIZE := 28.0
const CHIP_CONTENT_SEPARATION := 8
const GEAR_SIZE := 44.0

# Dev-only multiplayer test harnesses. These attach three dev_scripts/ nodes that each
# print a multi-line banner on _ready (and one writes a client-flag file), so they spam
# the console on EVERY normal launch. Off by default -- flip to true only when debugging
# the multiplayer auto-client/host handshake.
const ENABLE_DEV_TEST_HARNESS := false

# The shared Settings overlay, created on first open (see _settings_overlay).
# Null until the player actually asks for it -- the menu should not pay for a
# panel most visits never open.
var _settings_panel: SettingsPanel = null

func _ready() -> void:
	theme = MenuTheme.build()  # dark Legends-style menu look
	var background := MenuTheme.apply_backdrop(self)
	_install_menu_backdrop(background)
	_style_chrome()
	_build_top_bar()
	_build_resume_entry()

	if ENABLE_DEV_TEST_HARNESS:
		_attach_dev_test_harness()

	# Note: AutoClientDetector now runs as an autoload, so client detection
	# happens before this scene loads. If we reach here, we're not a client.
	# Connect button signals for normal menu operation
	if single_player_button:
		single_player_button.pressed.connect(_on_single_player_pressed)
		single_player_button.tooltip_text = "Solo play: Skirmish vs the AI, or an Arena roguelite run."
	if versus_button:
		versus_button.pressed.connect(_on_versus_pressed)
		versus_button.tooltip_text = "Face another player: local hot-seat or online."
	if compendium_button:
		compendium_button.pressed.connect(_on_compendium_pressed)
		compendium_button.tooltip_text = "Browse every unit, tile, status and map."
	if map_creator_button:
		map_creator_button.pressed.connect(_on_map_creator_pressed)
		map_creator_button.tooltip_text = "Build custom maps (early version)"
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

## Insert the ambient ember/spore + breathing-vignette layer directly above [param
## background] (the opaque "Background" ColorRect from [method MenuTheme.apply_backdrop])
## and below everything else -- content ("Layout" and its TopBar/CenterBlock/FooterMargin)
## keeps drawing on top. Positioned relative to [param background]'s actual sibling index
## rather than a hardcoded slot, so it stays correct regardless of tree order.
func _install_menu_backdrop(background: ColorRect) -> void:
	var backdrop := MenuBackdrop.new()
	add_child(backdrop)
	if background != null:
		move_child(backdrop, background.get_index() + 1)


func _style_chrome() -> void:
	"""Apply the shared gold-title / dim-caption treatment to the static labels."""
	MenuTheme.style_title(get_node_or_null("Layout/CenterBlock/Column/Title") as Label, 40)
	MenuTheme.style_subtitle(get_node_or_null("Layout/CenterBlock/Column/Subtitle") as Label)
	MenuTheme.style_caption(get_node_or_null("Layout/FooterMargin/Instructions") as Label)


## Build the top-right chrome row: a settings gear followed by the profile chip (a
## gold-bordered monogram badge plus the player's current rank name), anchored to the
## corner rather than living in the centered button column. Sits in its own 24px-margined
## row inserted as the FIRST child of "Layout" (a sibling of CenterBlock, not a member of
## Column/MenuButtons) so it reads as page chrome, like a header, rather than two more menu
## options. Code-built (like ProfileScreen's own cards) so the rank text can react to the
## live PlayerProfile read. See the TopBar geometry constants for the width arithmetic.
func _build_top_bar() -> void:
	var layout: VBoxContainer = get_node_or_null("Layout") as VBoxContainer
	if layout == null:
		return

	var top_bar := MarginContainer.new()
	top_bar.name = "TopBar"
	top_bar.add_theme_constant_override("margin_left", TOP_BAR_MARGIN)
	top_bar.add_theme_constant_override("margin_right", TOP_BAR_MARGIN)
	top_bar.add_theme_constant_override("margin_top", TOP_BAR_MARGIN)
	top_bar.add_theme_constant_override("margin_bottom", 0)

	var row := HBoxContainer.new()
	row.name = "TopBarRow"
	row.alignment = BoxContainer.ALIGNMENT_END  # push the pair to the top-right corner
	row.add_theme_constant_override("separation", TOP_BAR_SEPARATION)
	row.add_child(_make_settings_gear())
	row.add_child(_make_profile_chip())
	top_bar.add_child(row)

	layout.add_child(top_bar)
	layout.move_child(top_bar, 0)


## The settings gear. Same glyph, size and tooltip as the battle HUD's own gear
## (game/ui/layout/UILayoutManager.gd) because it opens the very same
## [SettingsPanel] -- one settings surface, reachable from both places.
func _make_settings_gear() -> Button:
	var gear := Button.new()
	gear.name = "SettingsButton"
	gear.text = "⚙"
	gear.tooltip_text = "Settings"
	gear.custom_minimum_size = Vector2(GEAR_SIZE, GEAR_SIZE)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.add_theme_font_size_override("font_size", 22)
	gear.pressed.connect(_on_settings_pressed)
	return gear


## The chip itself: a single Button (so hover/press/focus read from [MenuTheme] like any
## other menu button) with its badge + label laid out on an overlaid, click-through
## HBoxContainer -- the same "content over a plain button" trick CollectionScreen's roster
## rows use, so the whole chip is one click target rather than nested clickables.
func _make_profile_chip() -> Button:
	var chip := Button.new()
	chip.name = "ProfileChip"
	# STATED, not inferred: the overlaid content below is invisible to the layout
	# system (a Button is not a Container), so without an explicit width the chip
	# collapses to an empty button's padding and its content spills off-screen.
	chip.custom_minimum_size = Vector2(CHIP_WIDTH, CHIP_HEIGHT)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	chip.clip_contents = true  # belt-and-braces: nothing may ever paint outside the chip
	chip.text = ""
	chip.tooltip_text = "Your rank, achievements and collection."
	chip.pressed.connect(_on_profile_pressed)

	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = CHIP_PADDING
	content.offset_right = -CHIP_PADDING
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_BEGIN
	content.add_theme_constant_override("separation", CHIP_CONTENT_SEPARATION)
	chip.add_child(content)

	content.add_child(_make_profile_badge())

	# 200 - 12 - 28 - 8 - 12 = 140px of label room, which every rank name in
	# RankLadder fits at FONT_BODY. The ellipsis is the guarantee for the ones
	# that might not (a longer name, a bigger UI scale): the label TRIMS rather
	# than growing the row past the margin.
	var rank_label := Label.new()
	rank_label.name = "RankLabel"
	rank_label.text = _rank_display_text()
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_label.clip_text = true
	rank_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rank_label.add_theme_color_override("font_color", MenuTheme.CREAM)
	rank_label.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
	content.add_child(rank_label)

	return chip


## The monogram badge: a small gold-bordered, dark-filled, fully-rounded panel (a
## PanelContainer, since a bare Label carries no stylebox slot to paint a background on)
## holding a single letter -- "circular-feeling" at this size without needing a texture.
func _make_profile_badge() -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = "Badge"
	badge.custom_minimum_size = Vector2(CHIP_BADGE_SIZE, CHIP_BADGE_SIZE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := StyleBoxFlat.new()
	box.bg_color = MenuTheme.DARK
	box.set_corner_radius_all(int(CHIP_BADGE_SIZE / 2.0))
	box.set_border_width_all(2)
	box.border_color = MenuTheme.GOLD
	box.set_content_margin_all(0)
	badge.add_theme_stylebox_override("panel", box)

	var letter := Label.new()
	letter.text = PROFILE_MONOGRAM
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	letter.add_theme_color_override("font_color", MenuTheme.GOLD)
	letter.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
	badge.add_child(letter)

	return badge


## The rank name shown beside the badge, read null-safely off the PlayerProfile autoload
## the same way ProfileScreen does (lifetime points -> [RankLadder]). Falls back to the
## generic "PROFILE" label when the autoload is not present (a stripped test scene, an
## editor preview) rather than crashing or showing a stale rank.
func _rank_display_text() -> String:
	var profile: Node = get_node_or_null("/root/PlayerProfile")
	if profile == null or not profile.has_method("get_points_total"):
		return PROFILE_FALLBACK_LABEL
	return RankLadder.rank_for(int(profile.get_points_total())).to_upper()

# --- Resume battle ----------------------------------------------------------
#
# A battle saved with Save & Quit (see [BattleSaveManager]) surfaces here as a gold banner
# ABOVE Solo -- the first thing on the menu, because an unfinished battle is the thing the
# player most likely came back for. Built in code rather than in MainMenu.tscn, like the top
# bar, for the same reason: it only exists when there is something to resume, and its caption
# is read live off the save file.
#
# THE END-OF-DAY RULE lives here too. A paused CHALLENGE attempt expires when the UTC date
# rolls over, and expiring FORFEITS it (recorded as a played, un-cleared attempt). This is the
# first of the two places that is checked -- so an expired attempt never even offers a Resume
# button -- and [method BattleSaveManager.stage_resume] checks again at the moment of resume,
# so a menu left open across midnight cannot slip one through either.

const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"
const RESUME_EXPIRED_MESSAGE := "Challenge attempt expired — forfeited."

## The resume banner's caption (mode + map + save date), refreshed whenever it is built.
var _resume_caption: Label = null


func _build_resume_entry() -> void:
	"""Add the RESUME BATTLE banner to the top of the button column, but only when a valid,
	unexpired save exists. Expiring a stale challenge attempt happens here as a side effect --
	the banner is the moment the player would otherwise have seen it offered."""
	var snapshot: Dictionary = BattleSaveManager.peek_save()
	if snapshot.is_empty():
		return
	if BattleSaveManager.expire_if_needed(snapshot, BattleSaveManager.today_utc()):
		_show_status_message(RESUME_EXPIRED_MESSAGE)
		return

	var buttons: VBoxContainer = get_node_or_null(
		"Layout/CenterBlock/Column/MenuButtons") as VBoxContainer
	if buttons == null:
		return

	var block := VBoxContainer.new()
	block.name = "ResumeBlock"
	block.add_theme_constant_override("separation", 4)

	var button := Button.new()
	button.name = "ResumeButton"
	button.text = "▶  RESUME BATTLE"
	button.custom_minimum_size = Vector2(0, 50)
	button.tooltip_text = "Continue the battle you saved and quit."
	# Gold-on-dark, so it reads as the standout entry rather than a fifth menu option.
	button.add_theme_color_override("font_color", MenuTheme.GOLD)
	button.add_theme_color_override("font_hover_color", MenuTheme.CREAM)
	button.pressed.connect(_on_resume_pressed)
	block.add_child(button)

	_resume_caption = Label.new()
	_resume_caption.name = "ResumeCaption"
	_resume_caption.text = BattleSaveManager.describe(snapshot)
	_resume_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resume_caption.clip_text = true
	_resume_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_resume_caption.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	_resume_caption.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	block.add_child(_resume_caption)

	var spacer := Control.new()
	spacer.name = "ResumeSpacer"
	spacer.custom_minimum_size = Vector2(0, 12)
	block.add_child(spacer)

	buttons.add_child(block)
	buttons.move_child(block, 0)


func _on_resume_pressed() -> void:
	"""Stage the saved battle and go straight to it. stage_resume re-establishes the whole
	mode context (map, turn system, difficulty, and the campaign/challenge run arming) and
	re-checks the EOD rule; a false return means the save was expired or unusable and has
	already been discarded, so we report it and rebuild the menu without the banner."""
	var snapshot: Dictionary = BattleSaveManager.peek_save()
	if snapshot.is_empty() or not BattleSaveManager.stage_resume(snapshot, BattleSaveManager.today_utc()):
		_dismiss_resume_entry()
		_show_status_message(RESUME_EXPIRED_MESSAGE)
		return
	get_tree().change_scene_to_file(GAME_WORLD_SCENE)


func _dismiss_resume_entry() -> void:
	var buttons: Node = get_node_or_null("Layout/CenterBlock/Column/MenuButtons")
	if buttons == null:
		return
	var block: Node = buttons.get_node_or_null("ResumeBlock")
	if block != null:
		buttons.remove_child(block)
		block.queue_free()
	_resume_caption = null


func _attach_dev_test_harness() -> void:
	"""Attach the dev_scripts/ multiplayer test nodes. Gated behind ENABLE_DEV_TEST_HARNESS
	because each spams a banner on _ready (and test_autoclient_detector writes a client-flag
	file). Only for hands-on multiplayer handshake debugging."""
	var autoclient_test := Node.new()
	autoclient_test.name = "AutoClientDetectorTest"
	autoclient_test.set_script(load("res://dev_scripts/test_autoclient_detector.gd"))
	add_child(autoclient_test)

	var debug_test := Node.new()
	debug_test.name = "HostAutoClientDebugTest"
	debug_test.set_script(load("res://dev_scripts/test_host_auto_client_debug.gd"))
	add_child(debug_test)

	# NOTE: the end-to-end harness that used to be attached here drove the deleted legacy
	# stack (GameModeManager.start_network_multiplayer_host -> NetworkHandler -> the
	# Dictionary state simulator). The equivalent on NetSession is the two-process runner
	# dev_scripts/mp_loopback_runner.gd; see docs/NETWORK_TESTING.md.

func _show_auto_join_status() -> void:
	"""Show auto-join connection status"""
	# Hide menu buttons
	if single_player_button:
		single_player_button.visible = false
	if versus_button:
		versus_button.visible = false
	if quit_button:
		quit_button.visible = false
	
	# Show connection status
	var info = MultiplayerLauncher.get_auto_join_info()
	var status_text = "Auto-joining multiplayer game...\nConnecting to %s:%d as %s" % [info.address, info.port, info.player_name]
	
	_show_status_message(status_text)

func _show_status_message(message: String) -> void:
	"""Show a status message on the main menu"""
	# Create a status label if it doesn't exist
	var status_label = get_node_or_null("Layout/CenterBlock/Column/StatusLabel")
	if not status_label:
		status_label = Label.new()
		status_label.name = "StatusLabel"
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		var container = get_node("Layout/CenterBlock/Column")
		if container:
			container.add_child(status_label)
	
	if status_label:
		status_label.text = message
		status_label.visible = true

func _on_single_player_pressed() -> void:
	"""Handle Solo button press -- open the Solo mode picker (Skirmish / Arena Run)."""

	# Set up single player mode; the mode picker + Match Setup refine it from here.
	GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	GameSettings.set_player_count(1)  # Single player vs AI

	get_tree().change_scene_to_file("res://menus/SoloModeSelect.tscn")

func _on_versus_pressed() -> void:
	"""Handle Versus button press"""

	# Load multiplayer mode selection scene (restored)
	get_tree().change_scene_to_file("res://menus/MultiplayerModeSelection.tscn")

func _on_compendium_pressed() -> void:
	"""Handle Compendium button press"""
	get_tree().change_scene_to_file("res://menus/Compendium.tscn")

func _on_profile_pressed() -> void:
	"""Handle Profile button press -- open the rank / stats / achievements screen."""
	get_tree().change_scene_to_file(PROFILE_SCENE)

func _on_settings_pressed() -> void:
	"""Handle the top-bar gear -- open the shared Settings overlay ON TOP of the menu.

	Not a scene change: the menu stays mounted underneath, so closing the panel
	returns the player exactly where they were."""
	_settings_overlay().open()

## The Settings overlay, instantiated on first use and kept afterwards.
##
## Mounted as the LAST child of this scene root, which is what puts it above
## Background / MenuBackdrop / Layout (siblings draw in tree order). It themes
## itself in its own _ready, so it does not inherit the menu's MenuTheme -- it is
## the same amber card the battle HUD shows, which is the point: one panel, one
## look, wherever it is opened from.
func _settings_overlay() -> SettingsPanel:
	if _settings_panel != null and is_instance_valid(_settings_panel):
		return _settings_panel
	_settings_panel = SettingsPanel.new()
	_settings_panel.name = "SettingsPanel"
	add_child(_settings_panel)
	return _settings_panel

## True while the overlay exists AND is on screen. The guard every input path
## checks before acting on a menu shortcut.
func _settings_open() -> bool:
	return _settings_panel != null and is_instance_valid(_settings_panel) and _settings_panel.is_open()

func _on_map_creator_pressed() -> void:
	"""Handle Map Creator button press -- open the custom-map editor (early version)."""
	get_tree().change_scene_to_file("res://game/mapmaker/MapMakerScene.tscn")

func _on_quit_pressed() -> void:
	"""Handle Quit button press"""
	get_tree().quit()

func _show_not_implemented_message(message: String) -> void:
	"""Show a temporary message for unimplemented features"""
	# Create a simple popup
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.title = "Not Implemented"
	add_child(dialog)
	dialog.popup_centered()
	
	# Remove dialog after it's closed
	dialog.confirmed.connect(func(): dialog.queue_free())

# Handle input for quick navigation
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return

	# Cast once into a typed local rather than relying on `is`-narrowing to survive
	# an early return -- `event.keycode` off an InputEvent-typed name does not
	# resolve.
	var key := event as InputEventKey
	if key == null:
		return

	# ORDER MATTERS: while the Settings overlay is up it owns the keyboard. Escape
	# closes IT (one step back), never the game, and every other shortcut is
	# swallowed rather than firing a scene change out from under an open panel.
	# Both branches mark the event handled so nothing underneath sees it too.
	if _settings_open():
		if key.keycode == KEY_ESCAPE:
			_settings_panel.close()
		get_viewport().set_input_as_handled()
		return

	match key.keycode:
		KEY_1:
			_on_single_player_pressed()
		KEY_2:
			_on_versus_pressed()
		KEY_3:
			_on_compendium_pressed()
		KEY_4:
			_on_map_creator_pressed()
		KEY_P:
			_on_profile_pressed()
		KEY_S:
			_on_settings_pressed()
		KEY_ESCAPE:
			_on_quit_pressed()