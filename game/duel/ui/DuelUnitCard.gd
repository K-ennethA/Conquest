extends PanelContainer
class_name DuelUnitCard

## One combatant's HUD card in a duel (docs/design/DUEL_BATTLE.md §6.2): team-edged grove
## card, element crest, Cinzel name, element badge, speed, HP bar + numbers (shield
## included) and status chips. Built only from the theme factories (docs/UI_STYLE.md).
##
## Reads the live [Unit] every frame it is visible (cheap: a handful of labels), eases its
## HP bar toward the real value so a hit reads as a drain, and rebuilds its status chips
## only when the set changes. A unit freed on its KO reads as "Fainted". In a party duel the
## card also carries the side's team pips ([DuelPartyStrip]) and is rebound to whoever takes
## the station.

const CARD_WIDTH := 392.0
const CREST_PX := 54.0

var unit = null
var side: int = 0

var _crest: PanelContainer
var _name: Label
var _badge: PanelContainer
var _speed: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _chips: HFlowContainer
var _chip_sig: String = ""
## The side's team pips (party duels).
var party_strip: DuelPartyStrip = null
var _shown_frac: float = 1.0


func _init(p_side: int = 0) -> void:
	side = p_side


func _ready() -> void:
	name = "DuelUnitCard%d" % side
	custom_minimum_size = Vector2(CARD_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ConquestTheme.keep_style(self)
	add_theme_stylebox_override("panel", _box(null))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_crest = ConquestTheme.portrait("?", ConquestTheme.GOLD, _team(), CREST_PX)
	row.add_child(_crest)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	_name = Label.new()
	_name.name = "Name"
	_name.add_theme_font_override("font", MenuTheme.heading_font(1))
	_name.add_theme_font_size_override("font_size", ConquestTheme.FS_NAME)
	_name.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_name)
	_badge = ElementVisuals.make_badge(&"", ConquestTheme.FS_CAPTION)
	head.add_child(_badge)
	_speed = Label.new()
	_speed.name = "Speed"
	_speed.add_theme_font_size_override("font_size", ConquestTheme.FS_CAPTION)
	_speed.add_theme_color_override("font_color", ConquestTheme.TEXT_DIM)
	_speed.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_speed)

	_hp_bar = ConquestTheme.hp_bar(12.0)
	_hp_bar.name = "HpBar"
	col.add_child(_hp_bar)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(foot)
	_hp_text = Label.new()
	_hp_text.name = "HpText"
	_hp_text.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	_hp_text.add_theme_color_override("font_color", ConquestTheme.CREAM)
	foot.add_child(_hp_text)
	_chips = HFlowContainer.new()
	_chips.name = "Statuses"
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips.alignment = FlowContainer.ALIGNMENT_BEGIN
	_chips.add_theme_constant_override("h_separation", 4)
	_chips.add_theme_constant_override("v_separation", 4)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.visible = false
	col.add_child(_chips)
	party_strip = DuelPartyStrip.new()
	col.add_child(party_strip)
	refresh(true)


## PARTY DUELS: this side's team pips ([method DuelBattle.team_view]); hidden for one member.
func set_team(rows: Array) -> void:
	if party_strip != null:
		party_strip.set_rows(rows, _team())


## Point the card at [param p_unit].
func bind(p_unit) -> void:
	unit = p_unit
	_chip_sig = ""
	_shown_frac = _hp_frac()
	if is_inside_tree():
		add_theme_stylebox_override("panel", _box(unit))
		refresh(true)


func _process(delta: float) -> void:
	if visible:
		refresh(false, delta)


func refresh(snap: bool = false, delta: float = 0.0) -> void:
	if _name == null:
		return
	var alive: bool = _alive()
	var ch = unit.character_resource if alive and "character_resource" in unit else null
	var display: String = unit.get_display_name() if alive else _name.text
	_name.text = display
	if alive:
		var colors: Array = ConquestTheme.unit_portrait_colors(unit)
		ConquestTheme.set_portrait(_crest, display, colors[0], colors[1])
		ElementVisuals.update_badge(_badge, unit.get_element())
		_speed.text = "SPD %d" % int(unit.get_stat("speed"))
		var spd_base: int = int(ch.base_speed) if ch != null else int(unit.get_stat("speed"))
		_speed.add_theme_color_override("font_color",
			MoveStatVisuals.delta_color(spd_base, int(unit.get_stat("speed")), ConquestTheme.TEXT_DIM))
	var hp: int = int(unit.get_hp()) if alive else 0
	var max_hp: int = int(unit.max_health) if alive else 1
	var shield: int = int(unit.get_shield()) if alive and unit.has_method("get_shield") else 0
	var target := _hp_frac()
	if snap or delta <= 0.0:
		_shown_frac = target
	else:
		_shown_frac = move_toward(_shown_frac, target, maxf(delta * 0.8, absf(target - _shown_frac) * delta * 5.0))
	_hp_bar.value = _shown_frac
	ConquestTheme.tint_hp_bar(_hp_bar, _shown_frac)
	_hp_text.text = ShieldVisuals.hp_text(hp, max_hp, shield) if alive else "Fainted"
	_rebuild_chips(alive)


func _rebuild_chips(alive: bool) -> void:
	var groups: Array = StatusVisuals.group_by_id(StatusVisuals.active_conditions(unit)) if alive else []
	var sig := ""
	for g in groups:
		sig += StatusVisuals.chip_text(g["condition"], int(g["count"]), int(g["turns_left"])) + "|"
	if sig == _chip_sig:
		return
	_chip_sig = sig
	_chips.visible = not groups.is_empty()
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	for g in groups:
		var cond = g["condition"]
		var info: Dictionary = StatusVisuals.info_for(cond)
		var chip := ConquestTheme.chip(StatusVisuals.chip_text(cond, int(g["count"]), int(g["turns_left"])),
			info.get("color", ConquestTheme.GOLD), ConquestTheme.FS_CAPTION)
		chip.tooltip_text = StatusVisuals.describe_condition(cond)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		_chips.add_child(chip)


func _hp_frac() -> float:
	if not _alive():
		return 0.0
	var max_hp := maxf(1.0, float(unit.max_health))
	return clampf(float(unit.get_hp()) / max_hp, 0.0, 1.0)


func _alive() -> bool:
	return unit != null and is_instance_valid(unit) and unit.is_alive()


func _team() -> Color:
	return ConquestTheme.TEAM_BLUE if side == 0 else ConquestTheme.TEAM_RED


func _box(for_unit) -> StyleBox:
	var sb: OrnateStyleBox = ConquestTheme.unit_card_box(for_unit) if for_unit != null else ConquestTheme.panel_box()
	sb.accent_color = Color(_team(), 0.95)
	sb.accent_side = SIDE_LEFT if side == 1 else SIDE_RIGHT
	sb.accent_width = 4.0
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb
