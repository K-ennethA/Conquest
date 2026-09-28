extends Control

class_name MainMenu

## Title screen (illuminated-grove look). A slowly turning 3D diorama of one of the
## game's maps sits behind a left-hand command list; the focused command's one-line
## description shows under the list. Mouse hover and keyboard / gamepad focus are one
## highlight (MenuNav).
##
## Information architecture (kept from the menu IA restructure):
##   [Resume Battle]  -- only when a Save & Quit battle exists (BattleSaveManager)
##   Solo             -- SoloModeSelect: Campaign / Skirmish / Siege / Arena Run / Challenges
##   Versus           -- MultiplayerModeSelection: hot-seat or network
##   Compendium       -- the whole in-game reference (units, tiles, maps, weather, rules...)
##   Map Creator      -- the Map Maker (Back returns here)
##   Quit
## Page chrome in the top-right corner (not menu rows): the Settings gear (the same
## SettingsPanel the battle HUD opens, shown as a readable overlay) and the profile chip
## (rank crest + rank name -> ProfileScreen; Collection / gacha nest inside Profile).
##
## Built in code (the .tscn is only the root). Shortcuts: 1-4 = the four commands (shown
## as small numerals beside each), P = Profile, S = Settings (gamepad Start), Esc / B
## moves the cursor to Quit (a second Esc on Quit quits).

const DIORAMA_MAPS: Array[String] = [
	"res://game/maps/resources/elemental_crossroads.tres",
	"res://game/maps/resources/forgotten_forest.tres",
	"res://game/maps/resources/skirmish_arena.tres",
]

const SOLO_SCENE := "res://menus/SoloModeSelect.tscn"
const VERSUS_SCENE := "res://menus/MultiplayerModeSelection.tscn"
const COMPENDIUM_SCENE := "res://menus/Compendium.tscn"
const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
# Progression (rank, points, achievements) -- reached through the top-right profile chip,
# not a column entry. Collection (the cosmetic wardrobe + gacha) is a card on ProfileScreen.
const PROFILE_SCENE := "res://menus/ProfileScreen.tscn"
const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"

const ENTRIES := [
	{"id": "solo", "text": "Solo", "key": KEY_1,
		"desc": "Story journey, Campaign, Skirmish, Siege, Arena runs, Challenges and one-on-one Duels."},
	{"id": "versus", "text": "Versus", "key": KEY_2,
		"desc": "Two commanders, one battlefield. Play hot-seat on this device, or connect over the network."},
	{"id": "compendium", "text": "Compendium", "key": KEY_3,
		"desc": "Every unit, tile, map, weather, status and rule -- searchable, with the element chart."},
	{"id": "map_creator", "text": "Map Creator", "key": KEY_4,
		"desc": "Build your own battlefields -- floors, stairs, weather and spawn points -- and share them."},
	{"id": "quit", "text": "Quit", "key": KEY_NONE,
		"desc": "Close Conquest and return to the desktop."},
]

# The code-built profile chip: crest letter, and the no-autoload fallback label.
const PROFILE_MONOGRAM := "P"
const PROFILE_FALLBACK_LABEL := "PROFILE"
# Top-right chrome geometry. A Button is not a Container, so the chip's overlaid
# crest + label add nothing to its minimum size: the width is stated, and the rank
# label ellipsises inside it rather than spilling off-screen.
const CHIP_WIDTH := 220.0
const CHIP_HEIGHT := 48.0        # touch rule: >= 44px tall
const CHIP_PADDING := 10.0
const CHIP_CREST_SIZE := 32.0
const GEAR_SIZE := 48.0

const RESUME_EXPIRED_MESSAGE := "Challenge attempt expired — forfeited."

var single_player_button: Button   # the "Solo" row (name kept for callers)
var versus_button: Button
var compendium_button: Button
var map_creator_button: Button
var quit_button: Button
var settings_button: Button        # top-right gear
var profile_button: Button         # top-right rank chip
var resume_button: Button          # only while a saved battle exists

var _buttons: Array[Button] = []   # the menu rows, top to bottom (resume first if present)
var _list: VBoxContainer
var _desc_label: Label
var _status_panel: PanelContainer
var _status_label: Label
var _resume_caption: Label = null
# The shared Settings overlay, created on first open (most visits never open it).
var _settings_panel: SettingsPanel = null
var _diorama: MapPreview3D


func _ready() -> void:
	theme = MenuTheme.build()

	# Arriving at the main menu always ends any network match: close the session
	# and restore local play, so single-player / hotseat afterwards starts clean.
	var net_msg: String = ""
	if GameModeManager:
		if GameModeManager.has_method(&"end_network_session"):
			GameModeManager.end_network_session()
		if GameModeManager.has_method(&"consume_menu_message"):
			net_msg = GameModeManager.consume_menu_message()

	_build_ui()
	_build_resume_entry()
	_build_story_entry()
	if net_msg != "":
		_show_status_message(net_msg)
	MenuNav.focus_deferred(resume_button if resume_button != null else single_player_button)


# --- Layout ---------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var ground := ColorRect.new()
	ground.name = "Ground"
	ground.color = MenuTheme.BG_DEEP
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	var bd := MenuBackdrop.new()
	bd.name = "Backdrop"
	bd.motes = false
	bd.flourishes = false
	bd.vignette_strength = 0.0
	add_child(bd)

	_build_diorama()

	# Left-to-right scrim so the command list always reads over the diorama.
	var scrim := TextureRect.new()
	scrim.name = "Scrim"
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.38, 0.72, 1.0])
	g.colors = PackedColorArray([
		Color(MenuTheme.BG_DEEP, 0.96), Color(MenuTheme.BG_DEEP, 0.82),
		Color(MenuTheme.BG_DEEP, 0.15), Color(MenuTheme.BG_DEEP, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	scrim.texture = gt
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# Drifting gold motes + grove spores, vignette and the gilded corner flourishes.
	# (MenuBackdrop honours the Animations-off setting for the motes.)
	var atmosphere := MenuBackdrop.new()
	atmosphere.name = "Atmosphere"
	atmosphere.solid = false
	atmosphere.vignette_strength = 0.75
	add_child(atmosphere)

	var margin := MarginContainer.new()
	margin.name = "Page"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", MenuTheme.SP_PAGE)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 0)
	margin.add_child(col)

	var title := MenuKit.label("CONQUEST", &"DisplayLabel")
	title.name = "Title"
	col.add_child(title)

	var rule_row := HBoxContainer.new()
	rule_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	col.add_child(rule_row)
	var rule := GroveRule.new()
	rule.color = MenuTheme.GOLD
	rule.custom_minimum_size = Vector2(96, 12)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule_row.add_child(rule)
	var tagline := MenuKit.label("STRATEGIC TURN-BASED COMBAT", &"SectionLabel")
	tagline.name = "Subtitle"
	tagline.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	tagline.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	rule_row.add_child(tagline)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	col.add_child(gap)

	_list = VBoxContainer.new()
	_list.name = "MenuButtons"
	_list.custom_minimum_size = Vector2(430, 0)
	_list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_list.add_theme_constant_override("separation", 4)
	col.add_child(_list)

	for i in ENTRIES.size():
		var entry: Dictionary = ENTRIES[i]
		if entry["id"] == "quit":
			var sep := Control.new()
			sep.custom_minimum_size = Vector2(0, 10)
			_list.add_child(sep)
		var b := _make_entry(entry, i + 1 if int(entry["key"]) != KEY_NONE else 0)
		_list.add_child(b)
		_buttons.append(b)

	single_player_button = _buttons[0]
	versus_button = _buttons[1]
	compendium_button = _buttons[2]
	map_creator_button = _buttons[3]
	quit_button = _buttons[4]
	single_player_button.pressed.connect(_on_single_player_pressed)
	versus_button.pressed.connect(_on_versus_pressed)
	compendium_button.pressed.connect(_on_compendium_pressed)
	map_creator_button.pressed.connect(_on_map_creator_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	single_player_button.tooltip_text = "Solo play: Campaign, Skirmish, Siege, Arena Run or Challenges."
	versus_button.tooltip_text = "Face another player: local hot-seat or online."
	compendium_button.tooltip_text = "Browse every unit, tile, map, weather, status and rule."
	map_creator_button.tooltip_text = "Build custom maps."

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 14)
	col.add_child(gap2)

	_desc_label = MenuKit.label("", &"DimLabel", true)
	_desc_label.name = "Description"
	_desc_label.custom_minimum_size = Vector2(430, 56)
	_desc_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_desc_label)

	# Network / session messages (e.g. "The opponent disconnected", an expired save).
	_status_panel = MenuKit.card()
	_status_panel.name = "StatusPanel"
	_status_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_status_panel.custom_minimum_size = Vector2(430, 0)
	var status_sb := MenuTheme.accented_card(MenuTheme.ACCENT, SIDE_LEFT, MenuTheme.PANEL, 0.94)
	status_sb.content_margin_top = 12
	status_sb.content_margin_bottom = 12
	_status_panel.add_theme_stylebox_override("panel", status_sb)
	_status_panel.visible = false
	col.add_child(_status_panel)
	_status_label = MenuKit.label("", &"", true)
	_status_label.name = "StatusLabel"
	_status_panel.add_child(_status_label)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(filler)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", MenuTheme.SP_XL)
	col.add_child(footer)
	footer.add_child(MenuKit.key_hint("Up/Down", "D-Pad", "Choose"))
	MenuKit.add_standard_hints(footer, "Select", "Quit")
	footer.add_child(MenuKit.key_hint("P", "Right", "Profile"))
	footer.add_child(MenuKit.key_hint("S", "Start", "Settings"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var ver := String(ProjectSettings.get_setting("application/config/version", ""))
	var version := MenuKit.label(("v" + ver) if ver != "" else "Development build", &"MutedLabel")
	version.name = "Version"
	footer.add_child(version)

	_build_top_bar()
	_wire_focus()


func _make_entry(entry: Dictionary, number: int) -> Button:
	var b := Button.new()
	b.name = String(entry["id"]).capitalize().replace(" ", "") + "Button"
	if entry["id"] == "solo":
		b.name = "SinglePlayerButton"  # historical node name
	b.text = entry["text"]
	b.theme_type_variation = &"MenuItem"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 50)
	b.focus_mode = Control.FOCUS_ALL
	MenuNav.hover_focus(b)
	b.focus_entered.connect(_on_entry_focused.bind(String(entry["desc"])))

	if number > 0:
		# Quiet number-key shortcut at the right edge.
		var num := MenuKit.label(str(number), &"MutedLabel")
		num.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		num.offset_left = -34
		num.offset_right = -14
		num.offset_top = -12
		num.offset_bottom = 12
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(num)
	return b


## Top-right page chrome: the Settings gear followed by the profile chip, anchored to
## the corner rather than living in the command list, so they read as a header, not as
## two more menu options.
func _build_top_bar() -> void:
	var top_bar := MarginContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_bar.add_theme_constant_override("margin_right", MenuTheme.SP_PAGE)
	top_bar.add_theme_constant_override("margin_top", 36)
	add_child(top_bar)

	var row := HBoxContainer.new()
	row.name = "TopBarRow"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", MenuTheme.SP_S)
	top_bar.add_child(row)
	settings_button = _make_settings_gear()
	row.add_child(settings_button)
	profile_button = _make_profile_chip()
	row.add_child(profile_button)


## The settings gear: opens the very same [SettingsPanel] the battle HUD opens -- one
## settings surface, reachable from both places.
func _make_settings_gear() -> Button:
	var gear := Button.new()
	gear.name = "SettingsButton"
	# A drawn [GearIcon], not "⚙": the fonts have no gear glyph (tofu) -- the same drawn
	# gear the battle HUD's settings button carries.
	gear.text = ""
	gear.theme_type_variation = &"GhostButton"
	gear.tooltip_text = "Settings (S)"
	gear.custom_minimum_size = Vector2(GEAR_SIZE, GEAR_SIZE)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.add_theme_font_size_override("font_size", 22)
	gear.focus_mode = Control.FOCUS_ALL
	MenuNav.hover_focus(gear)
	gear.focus_entered.connect(_on_entry_focused.bind(
		"Animations, battle speed, audio, weather effects, camera and controls."))
	gear.pressed.connect(_on_settings_pressed)
	GearIcon.attach(gear)
	return gear


## The chip: one Button (so hover / press / focus read from the theme like any other
## control) with a small gold-rimmed crest + the player's rank name overlaid on a
## click-through HBox -- the whole chip is one click target.
func _make_profile_chip() -> Button:
	var chip := Button.new()
	chip.name = "ProfileChip"
	chip.theme_type_variation = &"GhostButton"
	chip.custom_minimum_size = Vector2(CHIP_WIDTH, CHIP_HEIGHT)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	chip.clip_contents = true
	chip.text = ""
	chip.tooltip_text = "Your rank, achievements and collection (P)."
	chip.focus_mode = Control.FOCUS_ALL
	MenuNav.hover_focus(chip)
	chip.focus_entered.connect(_on_entry_focused.bind(
		"Your rank, achievements and collection -- skins and recruits live here."))
	chip.pressed.connect(_on_profile_pressed)

	var content := HBoxContainer.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = CHIP_PADDING
	content.offset_right = -CHIP_PADDING
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_BEGIN
	content.add_theme_constant_override("separation", MenuTheme.SP_S)
	chip.add_child(content)

	var crest := MenuKit.crest(PROFILE_MONOGRAM, MenuTheme.PANEL_HI, MenuTheme.GOLD, CHIP_CREST_SIZE)
	crest.name = "Badge"
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(crest)

	var rank_label := Label.new()
	rank_label.name = "RankLabel"
	rank_label.text = _rank_display_text()
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_label.clip_text = true
	rank_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rank_label.add_theme_font_override("font", MenuTheme.heading_font())
	rank_label.add_theme_color_override("font_color", MenuTheme.CREAM)
	rank_label.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	content.add_child(rank_label)
	MenuKit.ignore_mouse(content)
	return chip


## The rank name shown in the chip, read null-safely off the PlayerProfile autoload the
## same way ProfileScreen does (lifetime points -> [RankLadder]). Falls back to "PROFILE"
## when the autoload is absent (a stripped test scene, an editor preview).
func _rank_display_text() -> String:
	var profile: Node = get_node_or_null("/root/PlayerProfile")
	if profile == null or not profile.has_method("get_points_total"):
		return PROFILE_FALLBACK_LABEL
	return RankLadder.rank_for(int(profile.get_points_total())).to_upper()


## Vertical focus wraps through the list; Right from any row reaches the top-right
## chrome (profile chip), Left / Down from the chrome returns to the list.
func _wire_focus() -> void:
	if _buttons.is_empty():
		return
	# Wrap vertical focus so Up on the first entry reaches Quit and back.
	_buttons[0].focus_neighbor_top = _buttons[0].get_path_to(_buttons[-1])
	_buttons[-1].focus_neighbor_bottom = _buttons[-1].get_path_to(_buttons[0])
	if profile_button == null or settings_button == null:
		return
	for b in _buttons:
		b.focus_neighbor_right = b.get_path_to(profile_button)
	profile_button.focus_neighbor_left = profile_button.get_path_to(settings_button)
	settings_button.focus_neighbor_right = settings_button.get_path_to(profile_button)
	settings_button.focus_neighbor_left = settings_button.get_path_to(_buttons[0])
	for chrome in [profile_button, settings_button]:
		var c: Button = chrome
		c.focus_neighbor_bottom = c.get_path_to(_buttons[0])
		c.focus_neighbor_top = c.get_path_to(_buttons[-1])


func _build_diorama() -> void:
	var path := ""
	for p in DIORAMA_MAPS:
		if ResourceLoader.exists(p):
			path = p
			break
	if path == "":
		return
	var res := load(path) as MapResource
	if res == null:
		return
	_diorama = MapPreview3D.new()
	_diorama.name = "Diorama"
	_diorama.framing = MapPreview3D.Framing.DIORAMA
	_diorama.transparent = true
	_diorama.show_spawns = false
	_diorama.turntable_speed = 0.05
	_diorama.lens_shift = -0.32
	_diorama.zoom_out = 1.15
	_diorama.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_diorama)
	_diorama.show_map(res)
	_diorama.map_root.rotation.y = 0.5


func _on_entry_focused(desc: String) -> void:
	if _desc_label != null:
		_desc_label.text = desc


func _show_status_message(message: String) -> void:
	"""Show a status message (why a network match ended, an expired save) under the menu."""
	if _status_label == null:
		return
	_status_label.text = message
	_status_panel.visible = true


# --- Resume battle --------------------------------------------------------------
#
# A battle saved with Save & Quit (see [BattleSaveManager]) surfaces as a gold row ABOVE
# Solo -- the first thing on the menu, because an unfinished battle is what the player most
# likely came back for. It only exists when there is something to resume, and its caption
# is read live off the save file.
#
# THE END-OF-DAY RULE lives here too. A paused CHALLENGE attempt expires when the UTC date
# rolls over, and expiring FORFEITS it (recorded as a played, un-cleared attempt). This is
# the first of the two places that is checked -- so an expired attempt is never offered --
# and [method BattleSaveManager.stage_resume] checks again at the moment of resume, so a
# menu left open across midnight cannot slip one through either.

func _build_resume_entry() -> void:
	var snapshot: Dictionary = BattleSaveManager.peek_save()
	if snapshot.is_empty():
		return
	if BattleSaveManager.expire_if_needed(snapshot, BattleSaveManager.today_utc()):
		_show_status_message(RESUME_EXPIRED_MESSAGE)
		return
	if _list == null:
		return

	var block := VBoxContainer.new()
	block.name = "ResumeBlock"
	block.add_theme_constant_override("separation", 0)

	resume_button = Button.new()
	resume_button.name = "ResumeButton"
	resume_button.text = "▶  Resume Battle"
	resume_button.theme_type_variation = &"MenuItem"
	resume_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	resume_button.custom_minimum_size = Vector2(0, 50)
	resume_button.focus_mode = Control.FOCUS_ALL
	resume_button.tooltip_text = "Continue the battle you saved and quit."
	# Gold text so it reads as the standout entry rather than one more command.
	resume_button.add_theme_color_override("font_color", MenuTheme.GOLD)
	resume_button.add_theme_color_override("font_hover_color", MenuTheme.GOLD_LITE)
	resume_button.add_theme_color_override("font_focus_color", MenuTheme.GOLD_LITE)
	MenuNav.hover_focus(resume_button)
	resume_button.pressed.connect(_on_resume_pressed)
	block.add_child(resume_button)

	_resume_caption = MenuKit.label(BattleSaveManager.describe(snapshot), &"MutedLabel")
	_resume_caption.name = "ResumeCaption"
	_resume_caption.clip_text = true
	_resume_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_resume_caption.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	# Indented to sit under the row's text (MenuItem rows reserve the leaf marker).
	var cap_margin := MarginContainer.new()
	cap_margin.add_theme_constant_override("margin_left", 48)
	cap_margin.add_theme_constant_override("margin_bottom", 8)
	cap_margin.add_child(_resume_caption)
	block.add_child(cap_margin)

	resume_button.focus_entered.connect(_on_entry_focused.bind(
		"Pick up the battle you saved and quit: " + _resume_caption.text))

	_list.add_child(block)
	_list.move_child(block, 0)
	_buttons.insert(0, resume_button)
	_wire_focus()


# --- Continue Journey (story mode) ---------------------------------------------------
#
# The most recently saved story journey surfaces as a gold row beside Resume Battle (same shape
# as _build_resume_entry): "Continue Journey" with its caption ("Mossway  ·  2h 15m").
# Absent when no journey is saved. Guarded: a build without StoryController shows nothing.

var journey_button: Button = null


func _build_story_entry() -> void:
	var story = get_node_or_null("/root/StoryController")
	if story == null or _list == null:
		return
	var slot: int = StorySaveManager.most_recent_slot()
	if slot <= 0:
		return
	var data: Dictionary = StorySaveManager.peek(slot)
	var names: Dictionary = {}
	for id in story.all_area_ids():
		names[id] = story.area_display_name(id)
	var block := VBoxContainer.new()
	block.name = "JourneyBlock"
	block.add_theme_constant_override("separation", 0)
	journey_button = Button.new()
	journey_button.name = "ContinueJourneyButton"
	journey_button.text = "▶  Continue Journey"
	journey_button.theme_type_variation = &"MenuItem"
	journey_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	journey_button.custom_minimum_size = Vector2(0, 50)
	journey_button.focus_mode = Control.FOCUS_ALL
	journey_button.add_theme_color_override("font_color", MenuTheme.GOLD)
	journey_button.add_theme_color_override("font_hover_color", MenuTheme.GOLD_LITE)
	journey_button.add_theme_color_override("font_focus_color", MenuTheme.GOLD_LITE)
	MenuNav.hover_focus(journey_button)
	journey_button.pressed.connect(_on_continue_journey_pressed.bind(slot))
	block.add_child(journey_button)
	var caption := MenuKit.label(StorySnapshot.describe(data, names), &"MutedLabel")
	caption.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	var cap_margin := MarginContainer.new()
	cap_margin.add_theme_constant_override("margin_left", 48)
	cap_margin.add_theme_constant_override("margin_bottom", 8)
	cap_margin.add_child(caption)
	block.add_child(cap_margin)
	journey_button.focus_entered.connect(_on_entry_focused.bind(
		"Walk on from where you last saved your journey: " + caption.text))
	var at: int = 1 if _list.get_node_or_null("ResumeBlock") != null else 0
	_list.add_child(block)
	_list.move_child(block, at)
	_buttons.insert(at, journey_button)
	_wire_focus()


func _on_continue_journey_pressed(slot: int) -> void:
	var story = get_node_or_null("/root/StoryController")
	if story == null:
		return
	var r: Dictionary = story.continue_journey(slot)
	if not bool(r.get("success", false)):
		_show_status_message("That journey could not be loaded.")
		return
	story.enter_overworld()


func _on_resume_pressed() -> void:
	"""Stage the saved battle and go straight to it. stage_resume re-establishes the whole
	mode context (map, turn system, difficulty, and the campaign/challenge run arming) and
	re-checks the EOD rule; a false return means the save was expired or unusable and has
	already been discarded, so report it and drop the entry."""
	var snapshot: Dictionary = BattleSaveManager.peek_save()
	if snapshot.is_empty() or not BattleSaveManager.stage_resume(snapshot, BattleSaveManager.today_utc()):
		_dismiss_resume_entry()
		_show_status_message(RESUME_EXPIRED_MESSAGE)
		return
	MenuNav.change_scene(self, GAME_WORLD_SCENE)


func _dismiss_resume_entry() -> void:
	if _list == null:
		return
	var block: Node = _list.get_node_or_null("ResumeBlock")
	if block != null:
		_list.remove_child(block)
		block.queue_free()
	if resume_button != null:
		_buttons.erase(resume_button)
	resume_button = null
	_resume_caption = null
	_wire_focus()
	MenuNav.focus_deferred(single_player_button)


# --- Actions ------------------------------------------------------------------------

func _on_single_player_pressed() -> void:
	# Solo -> SoloModeSelect (Campaign / Skirmish / Siege / Arena Run / Challenges); the
	# mode picker + Match Setup refine the settings from here.
	GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	GameSettings.set_player_count(1)  # Single player vs AI
	MenuNav.change_scene(self, SOLO_SCENE)


func _on_versus_pressed() -> void:
	MenuNav.change_scene(self, VERSUS_SCENE)


func _on_compendium_pressed() -> void:
	MenuNav.change_scene(self, COMPENDIUM_SCENE)


func _on_map_creator_pressed() -> void:
	# The Map Maker's Back / Esc returns to whoever opened it (here: the title screen).
	MapMakerScene.open_from(self, MAIN_MENU_SCENE)


func _on_profile_pressed() -> void:
	MenuNav.change_scene(self, PROFILE_SCENE)


func _on_settings_pressed() -> void:
	"""Open the shared Settings overlay ON TOP of the menu (not a scene change: closing
	it returns the player exactly where they were)."""
	_settings_overlay().open()


## The Settings overlay, instantiated on first use and kept afterwards. Hosted on its
## own CanvasLayer so it draws over the 3D diorama and the chrome; the panel themes
## itself with the shared navy + gold tokens, so it looks the same here as in battle.
func _settings_overlay() -> SettingsPanel:
	if _settings_panel != null and is_instance_valid(_settings_panel):
		return _settings_panel
	var layer := CanvasLayer.new()
	layer.name = "SettingsLayer"
	layer.layer = 10
	add_child(layer)
	_settings_panel = SettingsPanel.new()
	_settings_panel.name = "SettingsPanel"
	layer.add_child(_settings_panel)
	_settings_panel.visibility_changed.connect(_on_settings_visibility_changed)
	return _settings_panel


func _on_settings_visibility_changed() -> void:
	var open := _settings_open()
	# Keep keyboard / pad focus inside the panel while it is open.
	for b in _all_focusables():
		b.focus_mode = Control.FOCUS_NONE if open else Control.FOCUS_ALL
	if open:
		var first := _first_focusable(_settings_panel)
		if first != null:
			first.call_deferred(&"grab_focus")
	else:
		MenuNav.focus_deferred(settings_button)


func _all_focusables() -> Array[Button]:
	var out: Array[Button] = []
	out.append_array(_buttons)
	if settings_button != null:
		out.append(settings_button)
	if profile_button != null:
		out.append(profile_button)
	return out


func _first_focusable(node: Node) -> Control:
	for c in node.get_children():
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL \
				and (c as Control).is_visible_in_tree() and not (c is TabBar):
			return c
		var deeper := _first_focusable(c)
		if deeper != null:
			return deeper
	return null


## True while the overlay exists AND is on screen -- the guard every input path checks
## before acting on a menu shortcut.
func _settings_open() -> bool:
	return _settings_panel != null and is_instance_valid(_settings_panel) and _settings_panel.visible


func _on_quit_pressed() -> void:
	get_tree().quit()


# --- Input --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# While the Settings overlay is up it owns the input: Esc / B closes IT (one step
	# back), never the game, and no shortcut fires a scene change under an open panel.
	if _settings_open():
		if MenuNav.is_back_event(event):
			get_viewport().set_input_as_handled()
			_settings_panel.close()
		return

	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		# Esc moves the cursor to Quit; a second Esc on Quit quits.
		if quit_button != null and quit_button.has_focus():
			_on_quit_pressed()
		elif quit_button != null:
			quit_button.grab_focus()
		return

	if event is InputEventJoypadButton and event.pressed \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START:
		get_viewport().set_input_as_handled()
		_on_settings_pressed()
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	match key.keycode:
		KEY_P:
			get_viewport().set_input_as_handled()
			_on_profile_pressed()
			return
		KEY_S:
			get_viewport().set_input_as_handled()
			_on_settings_pressed()
			return
	var rows: Array[Button] = [single_player_button, versus_button, compendium_button,
		map_creator_button, quit_button]
	for i in ENTRIES.size():
		var code := int(ENTRIES[i]["key"])
		if code != KEY_NONE and key.keycode == code:
			get_viewport().set_input_as_handled()
			rows[i].grab_focus()
			rows[i].pressed.emit()
			return
