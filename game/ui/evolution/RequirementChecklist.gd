extends RefCounted
class_name RequirementChecklist

## The REQUIREMENTS CHECKLIST (docs/design/DECISIONS.md #27: "unmet requirements are shown as a
## checklist so players know what's missing") in the grove look. One static builder shared by the
## story Journey -> Party cards and Character Select's [EvolutionDetailBlock]:
##
##   ◆ Oakheart                       [READY]
##     ✓ Growth 3                      3/3
##     ○ Win 2 battles with it         1/2
##
## One block per edge leaving the form (a branching line shows every branch). Input: the entries
## of [method RosterLedger.checklists] / [method StoryGrowth.checklists] -- {edge, available,
## rows[, use_item]}. Presentation only; every row carries meta "met" / "skipped" for tests.

const MARK_SIZE := Vector2(14, 14)


## The checklist for [param entries]. Empty VBox (no children) when there are none.
static func build(entries: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "RequirementChecklist"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	var i: int = 0
	for entry in entries:
		if not (entry is Dictionary) or not (entry.get("edge", null) is EvolutionResource):
			continue
		box.add_child(_edge_block(entry, i))
		i += 1
	return box


static func _edge_block(entry: Dictionary, index: int) -> VBoxContainer:
	var edge: EvolutionResource = entry["edge"]
	var v := VBoxContainer.new()
	v.name = "Edge_%s" % String(edge.id)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 1)
	v.set_meta(&"available", bool(entry.get("available", false)))
	if index > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, MenuTheme.SP_XS)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(gap)

	# A flow row: the READY badge wraps under the name in a narrow column (Character Select).
	var head := HFlowContainer.new()
	head.name = "Head"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("h_separation", MenuTheme.SP_S)
	head.add_theme_constant_override("v_separation", 2)
	v.add_child(head)
	var to_c: CharacterResource = CharacterLibrary.get_character(edge.to_id)
	var gem := GroveGem.new()
	gem.color = MenuKit.element_color(String(to_c.element)) if to_c != null else MenuTheme.GOLD
	gem.custom_minimum_size = Vector2(10, 14)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(gem)
	var name_l := MenuKit.label("%s %s" % ["Promote to" if edge.is_promotion() else "Into",
		to_c.display_name if to_c != null else String(edge.to_id)], &"")
	name_l.name = "Target"
	name_l.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	name_l.add_theme_font_override("font", MenuTheme.bold_font())
	name_l.add_theme_color_override("font_color", MenuTheme.CREAM)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_l)
	var use_item: String = String(entry.get("use_item", ""))
	if bool(entry.get("available", false)):
		var ready := MenuKit.badge("READY", MenuTheme.SUCCESS)
		ready.name = "Ready"
		ready.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(ready)
	elif not use_item.is_empty():
		var item: ItemResource = ItemLibrary.get_item(use_item)
		var ready := MenuKit.badge("READY WITH %s" % (item.display_name.to_upper() if item != null else use_item.to_upper()),
			MenuTheme.GOLD)
		ready.name = "Ready"
		ready.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(ready)

	var r: int = 0
	for row in entry.get("rows", []):
		if row is Dictionary:
			v.add_child(_row(row, r))
			r += 1
	return v


static func _row(row: Dictionary, index: int) -> HBoxContainer:
	var met: bool = bool(row.get("met", false))
	var skipped: bool = bool(row.get("skipped", false))
	var h := HBoxContainer.new()
	h.name = "Req_%d" % index
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", MenuTheme.SP_S)
	h.set_meta(&"met", met)
	h.set_meta(&"skipped", skipped)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(4, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pad)
	var mark := Mark.new()
	mark.name = "Mark"
	mark.state = Mark.SKIPPED if skipped else (Mark.MET if met else Mark.UNMET)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mark)
	var text := MenuKit.label(String(row.get("text", "")), &"")
	text.name = "Text"
	text.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	text.add_theme_color_override("font_color", MenuTheme.CREAM if met else (MenuTheme.TEXT_MUTED if skipped else MenuTheme.TEXT_DIM))
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Wraps rather than widening its host (the narrow Character Select column).
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(110, 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(text)
	# A story requirement seen outside story (Character Select) can only be met in story mode.
	var story_only_here: bool = skipped or (bool(row.get("outside_story", false)) and not met)
	var prog: String = "story only" if story_only_here else String(row.get("progress", ""))
	if not prog.is_empty():
		var p := MenuKit.label(prog, &"")
		p.name = "Progress"
		p.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		p.add_theme_color_override("font_color", MenuTheme.SUCCESS if met else MenuTheme.TEXT_MUTED)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(p)
	return h


## "Growth 3 ✓ · Win 2 battles 1/2" -- a one-line plain-text summary (tooltips, logs).
static func summary(entry: Dictionary) -> String:
	var parts: PackedStringArray = []
	for row in entry.get("rows", []):
		if not (row is Dictionary):
			continue
		var t: String = String(row.get("text", ""))
		if bool(row.get("met", false)):
			t += " (done)"
		elif not String(row.get("progress", "")).is_empty():
			t += " (%s)" % String(row.get("progress", ""))
		parts.append(t)
	return " · ".join(parts)


## The row mark, drawn (no font glyph needed): a green tick when met, a hollow ring when not, a
## short dash when the requirement does not apply here (story only).
class Mark:
	extends Control

	const MET := 0
	const UNMET := 1
	const SKIPPED := 2

	var state: int = UNMET:
		set(v):
			state = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = RequirementChecklist.MARK_SIZE

	func _draw() -> void:
		var s: Vector2 = size
		var c: Vector2 = s * 0.5
		var r: float = minf(s.x, s.y) * 0.42
		match state:
			MET:
				draw_circle(c, r, Color(MenuTheme.SUCCESS, 0.22))
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.55, 0.0), c + Vector2(-r * 0.12, r * 0.45),
					c + Vector2(r * 0.6, -r * 0.5)]), MenuTheme.SUCCESS, 2.0, true)
			UNMET:
				draw_arc(c, r, 0.0, TAU, 24, MenuTheme.TEXT_MUTED, 1.5, true)
			SKIPPED:
				draw_line(c + Vector2(-r * 0.6, 0.0), c + Vector2(r * 0.6, 0.0), MenuTheme.TEXT_MUTED, 1.5, true)
