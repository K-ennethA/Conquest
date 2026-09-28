extends RefCounted
class_name GrowthGems

## Small, shared EVOLUTION widgets in the grove look (docs/UI_STYLE.md): the Growth gem row,
## the roster-card pips, and the end-screen growth rows. Static builders only, so each host
## screen (Character Select, GameOverScreen, a future duel results card) adds one call rather
## than a copy of the layout.
##
## Gold means earned: a lit gem is a [GroveGem] in GOLD, an unlit one a dim sunk gem.

const GEM_SIZE := Vector2(12, 16)
const CARD_GEM_SIZE := Vector2(11, 14)
## Unlit gem colour: a sunk, blue-grey gem that reads as "not yet" against the navy card.
const UNLIT := Color("3a4b86")


## A row of [param goal] gems, the first [param earned] lit. Empty (no children) for goal 0.
static func gem_row(earned: int, goal: int, gem_size: Vector2 = GEM_SIZE) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "GrowthGems"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	for i in range(maxi(0, goal)):
		var gem := GroveGem.new()
		gem.name = "Gem%d" % (i + 1)
		gem.custom_minimum_size = gem_size
		gem.color = MenuTheme.GOLD if i < earned else UNLIT
		gem.set_meta(&"lit", i < earned)
		row.add_child(gem)
	return row


## The pips overlaid on a Character Select roster card for [param char_id]: one gem per
## Growth its next evolution needs, anchored bottom-right. Null when the character has no
## Growth-based evolution (nothing to show, so nothing is added).
static func card_pips(char_id: String) -> Control:
	var goal: int = RosterLedger.next_growth_goal(char_id)
	if goal <= 0:
		return null
	var uid: String = RosterLedger.member_for_character(char_id)
	# Only the form the member currently IS is growing toward this goal; an older form of an
	# already-evolved line shows no pips (its card's detail pane says "Evolved").
	if String(RosterLedger.form_of(uid)) != char_id:
		return null
	var row := gem_row(mini(RosterLedger.growth_of(uid), goal), goal, CARD_GEM_SIZE)
	row.name = "GrowthPips"
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Clear of the card frame's corner clasp.
	row.offset_right = -24
	row.offset_bottom = -13
	row.tooltip_text = "Growth %d / %d" % [mini(RosterLedger.growth_of(uid), goal), goal]
	return row


## Fill [param box] with one line per growth award ([method GrowthTracker.growth_this_battle]
## rows), under a gold "GROWTH" heading: "Barkling +1 Growth (3/3)  Ready to evolve!". Rows
## for a form with no further evolution (goal 0) are omitted: growth nobody can spend is not
## news. Hides the box when nothing is left to show. Returns how many rows were added.
static func fill_result_rows(box: VBoxContainer, rows: Array, font_size: int) -> int:
	if box == null:
		return 0
	for child in box.get_children():
		box.remove_child(child)
		child.free()
	var shown: Array = []
	for r in rows:
		if r is Dictionary and int(r.get("goal", 0)) > 0:
			shown.append(r)
	box.visible = not shown.is_empty()
	if shown.is_empty():
		return 0

	var heading := Label.new()
	heading.name = "GrowthHeading"
	heading.text = "GROWTH"
	heading.add_theme_font_size_override("font_size", font_size)
	heading.add_theme_font_override("font", MenuTheme.heading_font(2))
	heading.add_theme_color_override("font_color", MenuTheme.GOLD)
	box.add_child(heading)

	for r in shown:
		var row := HBoxContainer.new()
		row.name = "Growth_" + String(r.get("uid", "")).validate_node_name()
		row.add_theme_constant_override("separation", 8)
		var goal: int = int(r.get("goal", 0))
		var total: int = int(r.get("total", 0))
		row.add_child(gem_row(mini(total, goal), goal))
		var label := Label.new()
		label.name = "Text"
		label.text = result_line(r)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", MenuTheme.CREAM)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if bool(r.get("ready", false)):
			var ready := Label.new()
			ready.name = "Ready"
			ready.text = "Ready to evolve!"
			ready.add_theme_font_override("font", MenuTheme.heading_font(1))
			ready.add_theme_font_size_override("font_size", font_size)
			ready.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
			row.add_child(ready)
		box.add_child(row)
	return shown.size()


## "Barkling +1 Growth (3/3)" for one award row.
static func result_line(r: Dictionary) -> String:
	var goal: int = int(r.get("goal", 0))
	var total: int = int(r.get("total", 0))
	return "%s +%d Growth (%d/%d)" % [String(r.get("name", r.get("uid", ""))),
		int(r.get("gained", 0)), mini(total, goal), goal]
