extends Control

class_name ProfileScreen

## The player's PROGRESSION screen: rank + points header, a Collection entry card, the
## lifetime record, and the achievement grid. Reached from the main menu's top-right
## profile chip. Read-only -- everything here is a view onto the [PlayerProfile] autoload;
## this screen never grants or spends (the Collection card only navigates; SkinShop owns
## the spending).
##
## Built in code on the shared grove kit ([MenuKit.build_page], [MenuTheme] type
## variations -- see docs/UI_STYLE.md), so the .tscn stays a one-node stub and the card
## layout reacts to the data rather than being frozen into the scene.
##
## 720p budget. MenuKit's header + footer leave the body ~466 of 720. Body rows (16 apart):
##   top row   rank crest-card | Collection card ............ 118
##   record    section 20 + 6 + inset card of 2 x 4 stats .. 150
##   achieve.  section 20 + 6 + the ONE EXPAND_FILL scroll (floor 120)
## = 118 + 150 + 26 + 120 + 2 * 16 = 446, so the footer (Back) always fits and the
## achievement scroll takes every spare pixel on a taller window.
##
## Every read is null-guarded: with the autoload missing (a stripped test scene, an editor
## preview) the screen still draws, showing a zeroed Recruit profile rather than crashing.
##
## Input: Cancel (Esc / B) goes back; Next page (Tab / R / RB) opens the Collection.

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
# The cosmetic wardrobe nests under Profile rather than sitting as its own main-menu
# entry. Guarded with ResourceLoader.exists the same way MainMenu used to guard it, since
# the skin economy ships the scene separately from this screen.
const COLLECTION_SCENE := "res://menus/CollectionScreen.tscn"

# Achievement cards per row. Three fits the page without the description wrapping to more
# than two lines at FS_CAPTION.
const ACHIEVEMENT_COLUMNS := 3

# Accents for the record, so a band of numbers is scannable by colour rather than being
# one undifferentiated block (grove state tokens: win / loss / neutral info).
const ACCENT_WIN := MenuTheme.SUCCESS
const ACCENT_LOSS := MenuTheme.DANGER
const ACCENT_NEUTRAL := MenuTheme.ACCENT

var _profile: Node = null
var _collection_card: Button = null
var _back_btn: Button = null


func _ready() -> void:
	_profile = get_node_or_null("/root/PlayerProfile")
	_build_ui()


# =====================================================================================
#  UI CONSTRUCTION
# =====================================================================================

func _build_ui() -> void:
	# Leaderboards are deliberately NOT here yet: this rank is the local cosmetic ladder,
	# and a competitive standing only becomes meaningful with ranked multiplayer.
	var page := MenuKit.build_page(self, [], "Profile",
		"Leaderboards arrive with ranked multiplayer -- this rank is your solo progression.")

	var top := HBoxContainer.new()
	top.name = "TopRow"
	top.add_theme_constant_override("separation", MenuTheme.SP_L)
	page.body.add_child(top)
	top.add_child(_build_rank_header())
	top.add_child(_build_collection_card())

	page.body.add_child(_build_stats_band())
	page.body.add_child(_build_achievements_band())

	_back_btn = MenuKit.button("Back", MenuKit.GHOST, 140)
	_back_btn.name = "BackButton"
	_back_btn.pressed.connect(_on_back_pressed)
	page.actions.add_child(_back_btn)

	if InputMap.has_action(&"cycle_next") and not _collection_card.disabled:
		page.hints.add_child(MenuKit.key_hint(
			InputActions.describe(&"cycle_next", false), InputActions.describe(&"cycle_next", true),
			"Collection"))
	page.hints.add_child(MenuKit.key_hint("Esc", "B", "Back"))

	_focus_later(_collection_card if not _collection_card.disabled else _back_btn)


## The rank card (a hero surface, so it wears the crest): tier name, spendable balance,
## and a progress bar toward the next tier.
func _build_rank_header() -> PanelContainer:
	var card := MenuKit.card(&"CrestCard")
	card.name = "RankCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 118.0)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var lifetime: int = _lifetime_points()

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", MenuTheme.SP_M)
	col.add_child(top)

	var rank := MenuKit.label(RankLadder.rank_for(lifetime).to_upper(), &"HeadingLabel")
	rank.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	rank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(rank)

	var balance := MenuKit.label("%d pts" % _spendable_points(), &"SubheadingLabel")
	balance.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(balance)

	# The theme's ProgressBar is the grove's gold fill in a sunk well.
	var bar := ProgressBar.new()
	bar.name = "RankProgress"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = RankLadder.progress_in_rank(lifetime)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 10.0)
	col.add_child(bar)

	var caption_text: String
	var next_pts: int = RankLadder.next_threshold(lifetime)
	if next_pts < 0:
		caption_text = "%d lifetime points  •  top rank reached" % lifetime
	else:
		caption_text = "%d lifetime points  •  %d to %s" % [
			lifetime, RankLadder.points_to_next(lifetime), RankLadder.rank_for(next_pts)
		]
	var caption := MenuKit.label(caption_text, &"DimLabel")
	caption.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	col.add_child(caption)

	return card


## Collection is nested one level under Profile rather than living as its own main-menu
## entry: a gold-edged selectable card routing to CollectionScreen. Disabled with a
## "coming soon" tooltip when that scene is not yet in the build, the same guard MainMenu
## used to apply before this card existed.
func _build_collection_card() -> Button:
	var available: bool = ResourceLoader.exists(COLLECTION_SCENE)

	var parts := MenuKit.option_card(Vector2(380.0, 118.0))
	var card: Button = parts["button"]
	card.name = "CollectionCard"
	card.disabled = not available
	card.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
	card.tooltip_text = ("Unit skins you own -- equip a look for each character."
			if available else "Coming soon: your unit-skin wardrobe.")
	card.pressed.connect(_on_collection_pressed)
	MenuKit.accent_card(card, MenuTheme.GOLD)
	MenuNav.hover_focus(card)
	_collection_card = card

	var content: VBoxContainer = parts["content"]
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 2)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_M)
	content.add_child(row)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)

	text_col.add_child(MenuKit.section("Collection"))
	var subtitle := MenuKit.label("Unit skins you own -- equip a look for each character.",
		&"DimLabel", true)
	subtitle.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	text_col.add_child(subtitle)

	var balance := MenuKit.label("%d pts" % _spendable_points(), &"SubheadingLabel")
	balance.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	balance.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(balance)

	MenuKit.ignore_mouse(card)
	return card


## The lifetime record: eight stat blocks (gold caption over a tinted value), four to a
## row, in one sunken well.
func _build_stats_band() -> VBoxContainer:
	var band := VBoxContainer.new()
	band.name = "RecordBand"
	band.add_theme_constant_override("separation", 6)
	band.add_child(MenuKit.section("Record"))

	var well := MenuKit.card(&"InsetPanel")
	band.add_child(well)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", MenuTheme.SP_XL)
	grid.add_theme_constant_override("v_separation", MenuTheme.SP_S)
	well.add_child(grid)

	var won: int = _stat("battles_won")
	var lost: int = _stat("battles_lost")
	var played: int = won + lost
	var win_rate: String = "--" if played <= 0 else "%d%%" % int(round(100.0 * float(won) / float(played)))

	grid.add_child(_make_stat_card("Battles Won", str(won), ACCENT_WIN))
	grid.add_child(_make_stat_card("Battles Lost", str(lost), ACCENT_LOSS))
	grid.add_child(_make_stat_card("Win Rate", win_rate, ACCENT_NEUTRAL))
	grid.add_child(_make_stat_card("Units Defeated", str(_stat("units_defeated")), ACCENT_NEUTRAL))
	grid.add_child(_make_stat_card("Chapters Cleared", str(_stat("campaign_chapters_cleared")), MenuTheme.GOLD))
	grid.add_child(_make_stat_card("Arena Rounds", str(_stat("arena_rounds_won")), MenuTheme.GOLD))
	grid.add_child(_make_stat_card("Challenges Won", str(_stat("challenges_won")), MenuTheme.GOLD))
	grid.add_child(_make_stat_card("Maps Created", str(_stat("maps_created")), ACCENT_NEUTRAL))

	return band


## One record entry: [MenuKit.stat_block] (gold small-caps caption over the value), the
## value tinted by [param accent].
func _make_stat_card(caption: String, value: String, accent: Color) -> Control:
	var block := MenuKit.stat_block(caption, value)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := block.get_child(block.get_child_count() - 1) as Label
	if value_label != null:
		value_label.add_theme_color_override("font_color", accent.lightened(0.25))
	return block


## The achievement grid: unlocked cards read gold with their unlock date, locked ones sit
## sunk behind a lock glyph but still show the hint, so the grid doubles as a to-do list.
func _build_achievements_band() -> VBoxContainer:
	var band := VBoxContainer.new()
	band.name = "AchievementsBand"
	band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	band.add_theme_constant_override("separation", 6)

	var rows: Array = AchievementData.all()
	var unlocked: int = 0
	for row in rows:
		if _has_achievement(String(row.get("id", ""))):
			unlocked += 1

	band.add_child(MenuKit.section("Achievements  (%d / %d)" % [unlocked, rows.size()]))

	var scroll := ScrollContainer.new()
	scroll.name = "AchievementScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 120 floor: this scroll is the page's ONLY flexible region -- its floor is what decides
	# whether the footer (Back) fits on a 720p screen (see the class budget). It EXPANDS to
	# absorb all spare height on taller windows anyway.
	scroll.custom_minimum_size = Vector2(0.0, 120.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	band.add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 14)  # clear of the scrollbar
	scroll.add_child(pad)

	var grid := GridContainer.new()
	grid.columns = ACHIEVEMENT_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", MenuTheme.SP_M)
	grid.add_theme_constant_override("v_separation", MenuTheme.SP_M)
	pad.add_child(grid)

	for row in rows:
		grid.add_child(_make_achievement_card(row))

	return band


func _make_achievement_card(row: Dictionary) -> PanelContainer:
	var id: String = String(row.get("id", ""))
	var is_unlocked: bool = _has_achievement(id)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 84.0)
	# Unlocked: a grove frame with a gold edge. Locked: the sunk frame, dim ornaments.
	var sb: OrnateStyleBox
	if is_unlocked:
		sb = MenuTheme.accented_card(MenuTheme.GOLD)
	else:
		sb = MenuTheme.card_box(MenuTheme.PANEL_SUNK, MenuTheme.BORDER_SOFT)
		sb.ornament_color = Color(MenuTheme.GOLD_DK, 0.4)
		sb.inner_line_color = Color(MenuTheme.GOLD, 0.12)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", sb)
	card.tooltip_text = String(row.get("desc", ""))

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	card.add_child(line)

	var badge := Label.new()
	badge.text = String(row.get("icon", "★")) if is_unlocked else "🔒"
	badge.add_theme_font_size_override("font_size", 24)
	badge.add_theme_color_override("font_color",
		MenuTheme.GOLD_LITE if is_unlocked else MenuTheme.TEXT_MUTED)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(badge)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(col)

	var name_label := MenuKit.label(String(row.get("name", id)), &"SubheadingLabel")
	name_label.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	name_label.add_theme_color_override("font_color",
		MenuTheme.GOLD_LITE if is_unlocked else MenuTheme.TEXT_MUTED)
	col.add_child(name_label)

	var desc := MenuKit.label(String(row.get("desc", "")),
		&"DimLabel" if is_unlocked else &"MutedLabel", true)
	desc.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(desc)

	if is_unlocked:
		var date := MenuKit.label(_format_date(_achievement_date(id)), &"SectionLabel")
		col.add_child(date)

	return card


# =====================================================================================
#  DATA READS  (all null-guarded -- a missing autoload renders a zeroed Recruit)
# =====================================================================================

func _lifetime_points() -> int:
	if _profile != null and _profile.has_method("get_points_total"):
		return int(_profile.get_points_total())
	return 0


func _spendable_points() -> int:
	if _profile != null and _profile.has_method("get_points"):
		return int(_profile.get_points())
	return 0


func _stat(key: String) -> int:
	if _profile != null and _profile.has_method("get_stat"):
		return int(_profile.get_stat(key))
	return 0


func _has_achievement(id: String) -> bool:
	if _profile != null and _profile.has_method("has_achievement"):
		return bool(_profile.has_achievement(id))
	return false


func _achievement_date(id: String) -> String:
	if _profile != null and _profile.has_method("achievement_date"):
		return String(_profile.achievement_date(id))
	return ""


## Trim a stored ISO timestamp ("2026-08-01T14:22:07") down to just the date for the card.
func _format_date(stamp: String) -> String:
	if stamp.is_empty():
		return ""
	return "Unlocked %s" % stamp.split("T")[0]


# =====================================================================================
#  NAVIGATION
# =====================================================================================

func _on_back_pressed() -> void:
	MenuNav.change_scene(self, MAIN_MENU_SCENE)


## Guarded like the card's own disabled state: the wardrobe screen ships separately from
## this one, so a stale keypress (or a card left enabled by a race) can never fail a scene
## change.
func _on_collection_pressed() -> void:
	if not ResourceLoader.exists(COLLECTION_SCENE):
		return
	MenuNav.change_scene(self, COLLECTION_SCENE)


## The Collection shortcut is the shared "next page" input (Tab / R / RB). Caught in
## _input, BEFORE focus navigation, because Tab would otherwise only move focus. (It used
## to be C, which is now one of Cancel's keys.)
func _input(event: InputEvent) -> void:
	if MenuNav.is_next_event(event):
		get_viewport().set_input_as_handled()
		_on_collection_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


## [MenuNav.focus_deferred], but safe when the control leaves the tree first (a repaint
## rebuilt it, or the screen closed) -- grab_focus() on a detached control is an engine error.
func _focus_later(c: Control) -> void:
	if c == null:
		return
	# Captured by instance id, not by reference: a freed capture is itself an engine error.
	var id: int = c.get_instance_id()
	(func() -> void:
		var ctl := instance_from_id(id) as Control
		if ctl != null and ctl.is_inside_tree() and ctl.is_visible_in_tree():
			ctl.grab_focus()).call_deferred()
