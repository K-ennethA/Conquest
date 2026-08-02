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

# Dev-only multiplayer test harnesses. These attach three dev_scripts/ nodes that each
# print a multi-line banner on _ready (and one writes a client-flag file), so they spam
# the console on EVERY normal launch. Off by default -- flip to true only when debugging
# the multiplayer auto-client/host handshake.
const ENABLE_DEV_TEST_HARNESS := false

func _ready() -> void:
	theme = MenuTheme.build()  # dark Legends-style menu look
	var background := MenuTheme.apply_backdrop(self)
	_install_menu_backdrop(background)
	_style_chrome()
	_build_profile_chip()

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


## Build the top-right profile chip: a gold-bordered monogram badge plus the player's
## current rank name, anchored to the corner rather than living in the centered button
## column. Sits in its own 24px-margined row inserted as the FIRST child of "Layout" (a
## sibling of CenterBlock, not a member of Column/MenuButtons) so it reads as page chrome,
## like a header, rather than another menu option. Code-built (like ProfileScreen's own
## cards) so the rank text can react to the live PlayerProfile read.
func _build_profile_chip() -> void:
	var layout: VBoxContainer = get_node_or_null("Layout") as VBoxContainer
	if layout == null:
		return

	var top_bar := MarginContainer.new()
	top_bar.name = "TopBar"
	top_bar.add_theme_constant_override("margin_left", 24)
	top_bar.add_theme_constant_override("margin_right", 24)
	top_bar.add_theme_constant_override("margin_top", 24)
	top_bar.add_theme_constant_override("margin_bottom", 0)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END  # push the chip to the top-right corner
	row.add_child(_make_profile_chip())
	top_bar.add_child(row)

	layout.add_child(top_bar)
	layout.move_child(top_bar, 0)


## The chip itself: a single Button (so hover/press/focus read from [MenuTheme] like any
## other menu button) with its badge + label laid out on an overlaid, click-through
## HBoxContainer -- the same "content over a plain button" trick CollectionScreen's roster
## rows use, so the whole chip is one click target rather than nested clickables.
func _make_profile_chip() -> Button:
	var chip := Button.new()
	chip.name = "ProfileChip"
	chip.custom_minimum_size = Vector2(0.0, 44.0)  # touch rule: >= 44px tall
	chip.text = ""
	chip.tooltip_text = "Your rank, achievements and collection."
	chip.pressed.connect(_on_profile_pressed)

	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12.0
	content.offset_right = -12.0
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 8)
	chip.add_child(content)

	content.add_child(_make_profile_badge())

	var rank_label := Label.new()
	rank_label.text = _rank_display_text()
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_label.add_theme_color_override("font_color", MenuTheme.CREAM)
	rank_label.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
	content.add_child(rank_label)

	return chip


## The monogram badge: a small gold-bordered, dark-filled, fully-rounded panel (a
## PanelContainer, since a bare Label carries no stylebox slot to paint a background on)
## holding a single letter -- "circular-feeling" at this size without needing a texture.
func _make_profile_badge() -> PanelContainer:
	const BADGE_SIZE := 28.0

	var badge := PanelContainer.new()
	badge.name = "Badge"
	badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := StyleBoxFlat.new()
	box.bg_color = MenuTheme.DARK
	box.set_corner_radius_all(int(BADGE_SIZE / 2.0))
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

	var e2e_test := Node.new()
	e2e_test.name = "EndToEndMultiplayerTest"
	e2e_test.set_script(load("res://dev_scripts/test_end_to_end_multiplayer.gd"))
	add_child(e2e_test)

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
	
	if event is InputEventKey:
		match event.keycode:
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
			KEY_ESCAPE:
				_on_quit_pressed()