extends Button
class_name DuelMoveRow

## One cell of the duel's 2x2 move grid (docs/design/DUEL_BATTLE.md §6.2): an option card
## with the move's element gem, Cinzel name, category glyph, PWR / ACC, cooldown badge +
## recharge bar, and a live FORECAST chip against the current foe ("▲ Strong ×1.25 · ~24 ·
## 95%"). The ultimate carries a gold star. A move that cannot be used is sunk (disabled).
##
## The forecast is [method MoveExecutor.preview_vs] -- the SAME function the hit resolves
## through (rule 9); nothing here computes damage.

const ROW_SIZE := Vector2(404, 78)

var slot: int = -1
var _unit = null
var _foe = null
var _board = null
var _gem: GroveGem
var _name: Label
var _star: Label
var _meta: Label
var _forecast: Label
var _cooldown: Label
var _bar: ProgressBar


func _init(p_slot: int = -1) -> void:
	slot = p_slot


func _ready() -> void:
	name = "MoveRow%d" % slot
	theme_type_variation = MenuKit.CARD
	custom_minimum_size = ROW_SIZE
	focus_mode = Control.FOCUS_ALL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ConquestTheme.keep_style(self)

	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 7)
	add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	_gem = GroveGem.new()
	_gem.custom_minimum_size = Vector2(16, 20)
	_gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_gem)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	_name = _label(ConquestTheme.FS_COMMAND, ConquestTheme.CREAM)
	_name.name = "Name"
	_name.add_theme_font_override("font", MenuTheme.heading_font(1))
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name)
	_star = _label(ConquestTheme.FS_SMALL, ConquestTheme.GOLD_LITE)
	_star.name = "Ultimate"
	_star.text = "★"
	_star.tooltip_text = "Ultimate"
	top.add_child(_star)
	_meta = _label(ConquestTheme.FS_CAPTION, ConquestTheme.TEXT_DIM)
	_meta.name = "Meta"
	top.add_child(_meta)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bottom)
	_forecast = _label(ConquestTheme.FS_SMALL, ConquestTheme.CREAM)
	_forecast.name = "Forecast"
	_forecast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_forecast.clip_text = true
	_forecast.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bottom.add_child(_forecast)
	_cooldown = _label(ConquestTheme.FS_CAPTION, ConquestTheme.WARNING)
	_cooldown.name = "Cooldown"
	bottom.add_child(_cooldown)
	_bar = MoveStatVisuals.make_recharge_bar()
	col.add_child(_bar)

	focus_entered.connect(func() -> void:
		add_theme_stylebox_override("normal", get_theme_stylebox("hover")))
	focus_exited.connect(func() -> void:
		remove_theme_stylebox_override("normal"))


func bind(unit, foe, board) -> void:
	_unit = unit
	_foe = foe
	_board = board
	refresh(true)


func move() -> MoveResource:
	if _unit == null or not is_instance_valid(_unit):
		return null
	return _unit.get_move(slot)


## Redraw for the live state; [param usable] is whether the engine lists the slot as legal.
func refresh(usable: bool) -> void:
	if _name == null:
		return
	var mv := move()
	visible = mv != null
	if mv == null:
		disabled = true
		return
	var el := ElementVisuals.of_move(mv)
	_gem.color = ElementVisuals.color_for(el) if String(el) != "" else ConquestTheme.GOLD_DK
	_name.text = mv.display_name_for(_unit)
	_star.visible = MoveResource.is_ultimate_move(mv, slot)
	_meta.text = "%s %s · ACC %d%%" % [_category_glyph(mv), _power_text(mv), roundi(mv.accuracy * 100.0)]
	var mc = _unit.get_moveset_controller()
	var remaining: int = int(mc.remaining(mv)) if mc != null else 0
	_cooldown.text = MoveStatVisuals.cooldown_badge(remaining, mv.cooldown)
	MoveStatVisuals.update_recharge_bar(_bar, remaining, mv.cooldown)
	_forecast.text = forecast_text(mv, _unit, _foe, _board)
	var label = _last_label if _last_label != null else &""
	_forecast.add_theme_color_override("font_color",
		ElementVisuals.effectiveness_color(label, ConquestTheme.CREAM) if _forecast.text != "" else ConquestTheme.TEXT_DIM)
	disabled = not usable
	var notes: Array = []
	if _unit.character_resource is DuelCharacter:
		notes = (_unit.character_resource as DuelCharacter).duel_notes.get(mv.move_id, [])
	tooltip_text = mv.full_description() + ("\n" + "\n".join(notes) if not notes.is_empty() else "")


var _last_label = null


## "▲ Strong ×1.25 · ~24 · 95%" for a damage move, "Self · Guard" style notes otherwise.
func forecast_text(mv: MoveResource, unit, foe, board) -> String:
	_last_label = null
	var pattern := mv.targeting_for(unit)
	if pattern == null:
		return ""
	if pattern.target_kind == CombatTypes.TargetKind.SELF:
		return "On self"
	if foe == null or not is_instance_valid(foe) or not DuelBrain.deals_damage(mv, unit):
		return "Status"
	var f := MoveExecutor.preview_vs(mv, unit, foe, board)
	_last_label = f.get("element_label")
	var parts: Array[String] = []
	var eff := ElementVisuals.effectiveness_text(float(f.get("element_mult", 1.0)), f.get("element_label"))
	if eff != "":
		parts.append(("▲ " if ElementVisuals.effectiveness_word(f.get("element_label", &"")) == "Strong" else "▼ ") + eff)
	parts.append("~%d" % int(f.get("damage", 0)))
	parts.append("%d%%" % roundi(float(f.get("hit_pct", 0.0))))
	if bool(f.get("lethal", false)):
		parts.append("KO")
	return " · ".join(parts)


static func _category_glyph(mv: MoveResource) -> String:
	match mv.category:
		CombatTypes.DamageCategory.MAGICAL:
			return "✦"
		CombatTypes.DamageCategory.TRUE:
			return "◆"
	return "⚔"


static func _power_text(mv: MoveResource) -> String:
	for e in mv.effects:
		if DamageMath.is_damage_effect(e):
			return "PWR %d" % int(e.get("power"))
	return "PWR —"


static func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
