extends Control

class_name ProfileScreen

## The player's PROGRESSION screen: rank + points header, lifetime stat cards, and the
## achievement grid. Reached from the main menu's "Profile" button. Read-only -- everything
## here is a view onto the [PlayerProfile] autoload; this screen never grants or spends.
##
## Layout follows the dark "Legends" register the other menus use ([MenuTheme]) on a 24 /
## 16 rhythm: a 24px page margin, 16px between the major bands (header -> stats -> achievements
## -> footer), and 8/12px inside a card. The whole page is built in code (like ChallengeBrowse
## and SoloModeSelect) so the .tscn stays a one-node stub and the card layout can react to the
## data rather than being frozen into the scene.
##
## Every read is null-guarded: with the autoload missing (a stripped test scene, an editor
## preview) the screen still draws, showing a zeroed Recruit profile rather than crashing.

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"

# Achievement cards per row. Three fits the 860px page without the description wrapping to
# more than two lines at FONT_CAPTION.
const ACHIEVEMENT_COLUMNS := 3
const PAGE_WIDTH := 860.0

# Muted green / red / blue accents for the stat cards, so a column of numbers is scannable
# by colour rather than being one undifferentiated block.
const ACCENT_WIN := Color("6fbf73")
const ACCENT_LOSS := Color("c46b6b")
const ACCENT_NEUTRAL := Color("6b8fc4")

var _profile: Node = null


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_profile = get_node_or_null("/root/PlayerProfile")
	_build_ui()


# =====================================================================================
#  UI CONSTRUCTION
# =====================================================================================

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(center)

	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(PAGE_WIDTH, 0.0)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 16)
	center.add_child(page)

	var title := Label.new()
	title.text = "PROFILE"
	page.add_child(title)
	MenuTheme.style_title(title, 40)

	page.add_child(_build_rank_header())
	page.add_child(_build_stats_band())
	page.add_child(_build_achievements_band())
	page.add_child(_build_footer())


## The rank card: tier name, spendable balance, and a progress bar toward the next tier.
func _build_rank_header() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuTheme.card_box(MenuTheme.GOLD))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	var lifetime: int = _lifetime_points()

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)

	var rank := Label.new()
	rank.text = RankLadder.rank_for(lifetime).to_upper()
	rank.add_theme_font_size_override("font_size", 28)
	rank.add_theme_color_override("font_color", MenuTheme.GOLD)
	rank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(rank)

	var balance := Label.new()
	balance.text = "%d pts" % _spendable_points()
	balance.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	balance.add_theme_color_override("font_color", MenuTheme.CREAM)
	balance.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(balance)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = RankLadder.progress_in_rank(lifetime)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 10.0)
	bar.add_theme_stylebox_override("background", _bar_box(Color(MenuTheme.DARK.r, MenuTheme.DARK.g, MenuTheme.DARK.b, 0.85)))
	bar.add_theme_stylebox_override("fill", _bar_box(MenuTheme.GOLD))
	col.add_child(bar)

	var caption := Label.new()
	var next_pts: int = RankLadder.next_threshold(lifetime)
	if next_pts < 0:
		caption.text = "%d lifetime points  •  top rank reached" % lifetime
	else:
		caption.text = "%d lifetime points  •  %d to %s" % [
			lifetime, RankLadder.points_to_next(lifetime), RankLadder.rank_for(next_pts)
		]
	caption.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	caption.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(caption)

	return card


## The lifetime record: one small card per number, four to a row.
func _build_stats_band() -> VBoxContainer:
	var band := VBoxContainer.new()
	band.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "RECORD"
	band.add_child(header)
	MenuTheme.style_section_header(header)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	band.add_child(grid)

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


func _make_stat_card(caption: String, value: String, accent: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", MenuTheme.card_box(accent))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 24)
	value_label.add_theme_color_override("font_color", MenuTheme.CREAM)
	col.add_child(value_label)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	caption_label.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(caption_label)

	return card


## The achievement grid: unlocked cards read gold with their unlock date, locked ones sit
## dimmed behind a lock glyph but still show the hint, so the grid doubles as a to-do list.
func _build_achievements_band() -> VBoxContainer:
	var band := VBoxContainer.new()
	band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	band.add_theme_constant_override("separation", 8)

	var rows: Array = AchievementData.all()
	var unlocked: int = 0
	for row in rows:
		if _has_achievement(String(row.get("id", ""))):
			unlocked += 1

	var header := Label.new()
	header.text = "ACHIEVEMENTS  (%d / %d)" % [unlocked, rows.size()]
	band.add_child(header)
	MenuTheme.style_section_header(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 240.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	band.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = ACHIEVEMENT_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	for row in rows:
		grid.add_child(_make_achievement_card(row))

	return band


func _make_achievement_card(row: Dictionary) -> PanelContainer:
	var id: String = String(row.get("id", ""))
	var is_unlocked: bool = _has_achievement(id)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 84.0)
	card.add_theme_stylebox_override("panel", MenuTheme.card_box(MenuTheme.GOLD if is_unlocked else MenuTheme.BORDER))
	card.tooltip_text = String(row.get("desc", ""))
	if not is_unlocked:
		card.modulate = Color(1.0, 1.0, 1.0, 0.55)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	card.add_child(line)

	var badge := Label.new()
	badge.text = String(row.get("icon", "★")) if is_unlocked else "🔒"
	badge.add_theme_font_size_override("font_size", 24)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(badge)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(col)

	var name_label := Label.new()
	name_label.text = String(row.get("name", id))
	name_label.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	name_label.add_theme_color_override("font_color", MenuTheme.GOLD if is_unlocked else MenuTheme.CREAM_DIM)
	col.add_child(name_label)

	var desc := Label.new()
	desc.text = String(row.get("desc", ""))
	desc.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	desc.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(desc)

	if is_unlocked:
		var date := Label.new()
		date.text = _format_date(_achievement_date(id))
		date.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		date.add_theme_color_override("font_color", MenuTheme.GOLD_DK)
		col.add_child(date)

	return card


func _build_footer() -> VBoxContainer:
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)

	# Leaderboards are deliberately NOT here yet: this rank is the local cosmetic ladder,
	# and a competitive standing only becomes meaningful with ranked multiplayer.
	var note := Label.new()
	note.text = "Leaderboards arrive with ranked multiplayer -- this rank is your solo progression."
	note.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	note.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(note)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0.0, 44.0)
	back.pressed.connect(_on_back_pressed)
	footer.add_child(back)

	var hint := Label.new()
	hint.text = "ESC back"
	footer.add_child(hint)
	MenuTheme.style_caption(hint)

	return footer


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


func _bar_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(5)
	return sb


# =====================================================================================
#  NAVIGATION
# =====================================================================================

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		_on_back_pressed()
