extends VBoxContainer
class_name EvolutionDetailBlock

## The compact GROWTH block in Character Select's detail header (docs/design/EVOLUTION.md §5),
## sized for the narrow column beside the unit's turntable so it is seen without scrolling:
##
##   GROWTH ◆◆◇ 2/3                        (a unit growing toward an evolution)
##   [Stage II · from Barkling]            (an evolved form)
##   Ready to evolve!                      (a short caption only when there is news)
##   [ EVOLVE ]  [x] Hold                  (EVOLVE only when an evolution is available)
##   ◆ Into Oakheart                       (the REQUIREMENTS CHECKLIST per next form --
##     ✓ Growth 3            3/3            DECISIONS.md #27, [RequirementChecklist];
##     ○ Win 2 battles       1/2            story-only requirements read "story only")
##
## Self-contained so the host screen adds it with one line and calls [method show_for] on every
## detail refresh; pressing EVOLVE raises [signal evolve_requested] and the host opens the
## [EvolutionScreen]. Hidden entirely for a character in no evolution line.
##
## Reads the [RosterLedger] (menus may; the battle never does). Its one write is the HOLD toggle
## (the open-mode member's "no automatic prompts" flag -- e.g. the standalone duel's results card
## offer), saved at once.

signal evolve_requested(uid: String, edges: Array)

var _uid: String = ""
var _char_id: String = ""
var _edges: Array = []

var _head: HBoxContainer = null
var _gems_slot: HBoxContainer = null
var _count_label: Label = null
var _tags: HBoxContainer = null
var _caption: Label = null
var _checklist_slot: VBoxContainer = null
var _actions: HFlowContainer = null
var evolve_button: Button = null
## HOLD (DECISIONS.md #27): no automatic evolve prompts for this member.
var hold_toggle: CheckButton = null


func _init() -> void:
	name = "EvolutionBlock"
	add_theme_constant_override("separation", MenuTheme.SP_XS)

	_head = HBoxContainer.new()
	_head.name = "GrowthHead"
	_head.add_theme_constant_override("separation", MenuTheme.SP_S)
	add_child(_head)
	var title := MenuKit.section("Growth")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head.add_child(title)
	_gems_slot = HBoxContainer.new()
	_gems_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head.add_child(_gems_slot)
	_count_label = MenuKit.label("", &"DimLabel")
	_count_label.name = "GrowthCount"
	_count_label.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head.add_child(_count_label)

	_tags = HBoxContainer.new()
	_tags.name = "StageTags"
	_tags.add_theme_constant_override("separation", 6)
	add_child(_tags)

	_caption = MenuKit.label("", &"", true)
	_caption.name = "EvolutionCaption"
	_caption.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	add_child(_caption)

	# A flow row: Hold wraps under EVOLVE when the detail column is narrow.
	_actions = HFlowContainer.new()
	_actions.name = "EvolveActions"
	_actions.add_theme_constant_override("h_separation", MenuTheme.SP_M)
	_actions.add_theme_constant_override("v_separation", MenuTheme.SP_XS)
	add_child(_actions)
	evolve_button = MenuKit.button("Evolve", MenuKit.PRIMARY, 150, 40)
	evolve_button.name = "EvolveButton"
	evolve_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	evolve_button.pressed.connect(_on_evolve_pressed)
	_actions.add_child(evolve_button)
	hold_toggle = CheckButton.new()
	hold_toggle.name = "HoldToggle"
	hold_toggle.text = "Hold"
	hold_toggle.focus_mode = Control.FOCUS_ALL
	hold_toggle.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	hold_toggle.tooltip_text = "Hold: no automatic evolution prompts (e.g. after a duel). EVOLVE here still works."
	hold_toggle.toggled.connect(_on_hold_toggled)
	MenuNav.hover_focus(hold_toggle)
	_actions.add_child(hold_toggle)

	# Under the actions, so EVOLVE stays in view in the header without scrolling.
	_checklist_slot = VBoxContainer.new()
	_checklist_slot.name = "ChecklistSlot"
	_checklist_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_checklist_slot)
	visible = false


## Refresh for [param char_id]. Returns true when the block is shown.
func show_for(char_id: String) -> bool:
	_char_id = char_id
	_uid = RosterLedger.member_for_character(char_id)
	_edges.clear()
	if char_id.is_empty() or not EvolutionLibrary.in_any_line(char_id):
		visible = false
		return false
	visible = true

	var form: String = String(RosterLedger.form_of(_uid))
	var growth: int = RosterLedger.growth_of(_uid)
	var goal: int = RosterLedger.next_growth_goal(char_id)
	var is_current: bool = form == char_id
	if is_current:
		for e in RosterLedger.available_evolutions(_uid):
			_edges.append(e)

	# Head: gems toward the next goal -- only for the form the member currently is.
	for c in _gems_slot.get_children():
		_gems_slot.remove_child(c)
		c.free()
	_head.visible = goal > 0 and is_current
	if _head.visible:
		_gems_slot.add_child(GrowthGems.gem_row(mini(growth, goal), goal))
		_count_label.text = "%d/%d" % [mini(growth, goal), goal]
	_head.tooltip_text = _goal_text(char_id)
	for c in _head.get_children():
		if c is Control:
			(c as Control).tooltip_text = _head.tooltip_text

	# Stage badge: evolved forms name where they came from.
	for c in _tags.get_children():
		_tags.remove_child(c)
		c.free()
	var parent: StringName = EvolutionLibrary.parent_of(char_id)
	if parent != &"":
		_tags.add_child(MenuKit.badge("Stage %s · from %s" % [
			_roman(EvolutionLibrary.stage_of(char_id)), _name_of(parent)], MenuTheme.GOLD))
	_tags.visible = _tags.get_child_count() > 0

	# The checklist of what the member still needs, per next form (only for the form it IS).
	for c in _checklist_slot.get_children():
		_checklist_slot.remove_child(c)
		c.free()
	var entries: Array[Dictionary] = []
	if is_current:
		entries = RosterLedger.checklists(_uid)
	if not entries.is_empty():
		_checklist_slot.add_child(RequirementChecklist.build(entries))
	_checklist_slot.visible = not entries.is_empty()

	_caption.text = _caption_text(char_id, form, is_current)
	_caption.visible = not _caption.text.is_empty()
	_caption.add_theme_color_override("font_color",
		MenuTheme.GOLD_LITE if not _edges.is_empty() else MenuTheme.TEXT_MUTED)
	evolve_button.visible = not _edges.is_empty()
	if not _edges.is_empty():
		evolve_button.text = (_edges[0] as EvolutionResource).verb()
	hold_toggle.visible = not entries.is_empty()
	hold_toggle.set_pressed_no_signal(RosterLedger.is_held(_uid))
	_actions.visible = evolve_button.visible or hold_toggle.visible
	return true


## The checklist rows currently shown (tests): [{edge_id, met, skipped}] in order.
func checklist_rows() -> Array:
	var out: Array = []
	for block in _checklist_slot.find_children("Edge_*", "", true, false):
		for row in block.get_children():
			if row.has_meta(&"met"):
				out.append({"edge_id": String(block.name).trim_prefix("Edge_"), "met": bool(row.get_meta(&"met")),
					"skipped": bool(row.get_meta(&"skipped"))})
	return out


func _on_hold_toggled(on: bool) -> void:
	if _uid.is_empty():
		return
	RosterLedger.set_hold(_uid, on)
	RosterLedger.save()


## Only NEWS gets a visible caption; the goal itself lives in the gems' tooltip.
func _caption_text(char_id: String, form: String, is_current: bool) -> String:
	if not is_current and EvolutionLibrary.line_of(char_id).has(StringName(form)) \
			and EvolutionLibrary.stage_of(form) > EvolutionLibrary.stage_of(char_id):
		return "Evolved into %s" % _name_of(StringName(form))
	if not _edges.is_empty():
		return "Ready to be promoted!" if (_edges[0] as EvolutionResource).is_promotion() else "Ready to evolve!"
	if RosterLedger.is_held(_uid) and is_current:
		return "On hold -- no automatic prompts."
	return ""


## "Evolves into Oakheart at Growth 3. ..." (tooltip), or "Final form".
static func _goal_text(char_id: String) -> String:
	var parts: PackedStringArray = []
	for e in EvolutionLibrary.edges_from(char_id):
		parts.append("%s (needs %s)" % [_name_of(e.to_id), e.describe_triggers()])
	if parts.is_empty():
		return "Final form"
	return "Evolves into " + ", ".join(parts) + ". Earn Growth by surviving won battles."


func _on_evolve_pressed() -> void:
	if _edges.is_empty():
		return
	evolve_requested.emit(_uid, _edges.duplicate())


static func _name_of(id: StringName) -> String:
	var c: CharacterResource = CharacterLibrary.get_character(id)
	return c.display_name if c != null else String(id).capitalize()


static func _roman(n: int) -> String:
	var numerals: Array[String] = ["I", "II", "III", "IV", "V"]
	return numerals[n - 1] if n >= 1 and n <= numerals.size() else str(n)
