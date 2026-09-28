extends VBoxContainer
class_name EvolutionDetailBlock

## The compact GROWTH block in Character Select's detail header (docs/design/EVOLUTION.md §5),
## sized for the narrow column beside the unit's turntable so it is seen without scrolling:
##
##   GROWTH ◆◆◇ 2/3                        (a unit growing toward an evolution)
##   [Stage II · from Barkling]            (an evolved form)
##   Ready to evolve!                      (a short caption only when there is news)
##   [ EVOLVE ]                            (only when an evolution is available)
##
## Self-contained so the host screen adds it with one line and calls [method show_for] on every
## detail refresh; pressing EVOLVE raises [signal evolve_requested] and the host opens the
## [EvolutionScreen]. Hidden entirely for a character in no evolution line.
##
## Reads the [RosterLedger] (menus may; the battle never does) and never writes it.

signal evolve_requested(uid: String, edges: Array)

var _uid: String = ""
var _char_id: String = ""
var _edges: Array = []

var _head: HBoxContainer = null
var _gems_slot: HBoxContainer = null
var _count_label: Label = null
var _tags: HBoxContainer = null
var _caption: Label = null
var evolve_button: Button = null


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

	evolve_button = MenuKit.button("Evolve", MenuKit.PRIMARY, 150, 40)
	evolve_button.name = "EvolveButton"
	evolve_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	evolve_button.pressed.connect(_on_evolve_pressed)
	add_child(evolve_button)
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

	_caption.text = _caption_text(char_id, form, is_current)
	_caption.visible = not _caption.text.is_empty()
	_caption.add_theme_color_override("font_color",
		MenuTheme.GOLD_LITE if not _edges.is_empty() else MenuTheme.TEXT_MUTED)
	evolve_button.visible = not _edges.is_empty()
	return true


## Only NEWS gets a visible caption; the goal itself lives in the gems' tooltip.
func _caption_text(char_id: String, form: String, is_current: bool) -> String:
	if not is_current and EvolutionLibrary.line_of(char_id).has(StringName(form)) \
			and EvolutionLibrary.stage_of(form) > EvolutionLibrary.stage_of(char_id):
		return "Evolved into %s" % _name_of(StringName(form))
	if not _edges.is_empty():
		return "Ready to evolve!"
	return ""


## "Evolves into Oakheart at Growth 3. ..." (tooltip), or "Final form".
static func _goal_text(char_id: String) -> String:
	var parts: PackedStringArray = []
	for e in EvolutionLibrary.edges_from(char_id):
		parts.append("%s at %s" % [_name_of(e.to_id), e.describe_triggers()])
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
