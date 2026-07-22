extends Control

class_name CombatForecastPanel

# Fire-Emblem-style COMBAT FORECAST: a compact, non-modal floating overlay that
# predicts the outcome of an offensive move while the player is aiming it at an
# enemy. PREVIEW ONLY -- it reads MoveExecutor.preview_vs() (which never rolls
# RNG or mutates state) and just renders the numbers, so it is purely additive.
#
# Code-built (no .tscn) exactly like MoveSelectionPanel: it is top_level, anchors
# itself over the battlefield, and calls ConquestTheme.apply_to(self) for the
# amber HUD look. Unlike MoveSelectionPanel it is NON-modal: no dim backdrop and
# mouse_filter = IGNORE everywhere, so it never blocks clicks on the board.
#
# Positioned top-center so it never overlaps the right-edge sidebar.

const CARD_WIDTH := 360.0
## Distance from the TOP edge the card floats at. Sits just below the slim turn chip
## (~56px top bar), so it no longer overlaps the banner but still reliably renders
## (a bottom-anchored grow collapsed to zero height -- the "forecast is gone" bug).
const TOP_MARGIN := 70.0

# --- Node references (built once in _ready, only re-populated in show_forecast) --
var _card: PanelContainer
var _element_stripe: ColorRect
var _attacker_name: Label
var _attacker_bar: ProgressBar
var _attacker_hp: Label
var _defender_name: Label
var _defender_bar: ProgressBar
var _defender_hp: Label
var _hit_value: Label
var _dmg_value: Label
var _crit_value: Label
var _result_value: Label
var _lethal_label: Label

func _ready() -> void:
	name = "CombatForecastPanel"

	# Detach from the sidebar parent's layout: top_level lets the parent Container skip
	# us. BUT a Control's anchors still resolve against its PARENT's rect, and our parent
	# is UnitActionsPanel inside the ~220px sidebar -- so PRESET_FULL_RECT would size us
	# to the sidebar, not the screen, dumping the centred card off-view (the "forecast is
	# off-screen" bug). Instead we explicitly cover the whole VIEWPORT (see
	# _cover_viewport) and keep it in sync on window resize, so the card's centre anchor
	# always resolves against the real 1280x720 game window.
	top_level = true
	_cover_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_cover_viewport):
		vp.size_changed.connect(_cover_viewport)

	# Non-modal: never eat mouse input. The whole subtree is set IGNORE below so a
	# click during targeting always reaches the board/cursor underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Draw above sibling HUD panels; absolute z (z_as_relative = false).
	z_as_relative = false
	z_index = 90

	_create_ui()
	visible = false

func _create_ui() -> void:
	# The floating card, anchored to the BOTTOM-CENTER of the viewport: clear of the
	# top-center turn banner (which it used to render on top of) and the right-edge
	# sidebar, in the otherwise-empty bottom strip. Grows UPWARD from the bottom margin
	# to fit its content, so it can never push off the bottom of the screen.
	_card = PanelContainer.new()
	_card.name = "ForecastCard"
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.0
	_card.anchor_bottom = 0.0
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_END
	_card.offset_left = -CARD_WIDTH * 0.5
	_card.offset_right = CARD_WIDTH * 0.5
	_card.offset_top = TOP_MARGIN
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 6)
	root_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(root_vb)

	# Element accent stripe (Pokemon-style type cue), colour set per-move.
	_element_stripe = ColorRect.new()
	_element_stripe.color = ConquestTheme.AMBER
	_element_stripe.custom_minimum_size = Vector2(0, 4)
	_element_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_element_stripe)

	var title := Label.new()
	title.text = "BATTLE FORECAST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(title)

	# Attacker | vs | Defender row.
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 10)
	sides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(sides)

	var attacker_col := _build_side()
	_attacker_name = attacker_col["name"]
	_attacker_bar = attacker_col["bar"]
	_attacker_hp = attacker_col["hp"]
	attacker_col["root"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.add_child(attacker_col["root"])

	var vs := Label.new()
	vs.text = "vs"
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sides.add_child(vs)

	var defender_col := _build_side()
	_defender_name = defender_col["name"]
	_defender_bar = defender_col["bar"]
	_defender_hp = defender_col["hp"]
	defender_col["root"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.add_child(defender_col["root"])

	# Exchange stats plate (dark inset, cream text).
	var plate := PanelContainer.new()
	plate.name = "StatsPlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(plate)

	var stats_vb := VBoxContainer.new()
	stats_vb.add_theme_constant_override("separation", 3)
	stats_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(stats_vb)

	_hit_value = _add_stat_row(stats_vb, "Hit")
	_dmg_value = _add_stat_row(stats_vb, "Damage")
	_crit_value = _add_stat_row(stats_vb, "Crit")
	_result_value = _add_stat_row(stats_vb, "HP")

	_lethal_label = Label.new()
	_lethal_label.text = "LETHAL"
	_lethal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lethal_label.add_theme_font_size_override("font_size", 16)
	_lethal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lethal_label.visible = false
	stats_vb.add_child(_lethal_label)

	# Apply the amber HUD theme to the whole subtree FIRST (it strips baked-in
	# font colours / per-panel styleboxes), THEN layer our local plate + text
	# overrides so they survive.
	ConquestTheme.apply_to(self)

	# Dark inset plate behind the exchange stats, cream text so it reads on it.
	plate.add_theme_stylebox_override("panel", ConquestTheme.plate_box())
	for lbl in [_hit_value, _dmg_value, _crit_value, _result_value]:
		lbl.add_theme_color_override("font_color", ConquestTheme.CREAM)
	for row in stats_vb.get_children():
		if row is HBoxContainer:
			for child in row.get_children():
				if child is Label:
					child.add_theme_color_override("font_color", ConquestTheme.CREAM_DIM)
	_hit_value.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_dmg_value.add_theme_color_override("font_color", ConquestTheme.HIT_ORANGE)
	_result_value.add_theme_color_override("font_color", ConquestTheme.HP_CYAN)
	_lethal_label.add_theme_color_override("font_color", ConquestTheme.HIT_ORANGE)

func _build_side() -> Dictionary:
	"""One combatant column: name label + cyan HP bar + 'current/max' label."""
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_lbl := Label.new()
	name_lbl.text = "-"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_lbl)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0
	bar.max_value = 1
	bar.value = 1
	bar.custom_minimum_size = Vector2(140, 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(bar)

	var hp_lbl := Label.new()
	hp_lbl.text = "-/-"
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_lbl.add_theme_font_size_override("font_size", 12)
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hp_lbl)

	return {"root": vb, "name": name_lbl, "bar": bar, "hp": hp_lbl}

func _add_stat_row(parent: VBoxContainer, label_text: String) -> Label:
	"""A 'Label ....... value' row; returns the (right-aligned) value Label."""
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var key := Label.new()
	key.text = label_text
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key)

	var value := Label.new()
	value.text = "-"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(value)

	parent.add_child(row)
	return value

# --- Public API -------------------------------------------------------------

func show_forecast(attacker, defender, move: MoveResource) -> void:
	"""Populate the forecast for `attacker` using `move` against `defender`, then
	show it. Non-mutating: reads MoveExecutor.preview_vs() only. No-op (hides) on
	missing arguments."""
	if attacker == null or defender == null or move == null:
		hide_forecast()
		return

	# Attacker column.
	_attacker_name.text = _name_of(attacker)
	var att_hp := _hp_of(attacker)
	var att_max := _max_hp_of(attacker)
	_attacker_bar.max_value = maxi(1, att_max)
	_attacker_bar.value = clampi(att_hp, 0, maxi(1, att_max))
	_attacker_hp.text = "%d/%d" % [att_hp, att_max]

	# Element accent stripe.
	_element_stripe.color = ConquestTheme.element_color(String(move.element))

	var preview: Dictionary = MoveExecutor.preview_vs(move, attacker, defender)

	# Defender column.
	var target_hp: int = int(preview.get("target_hp", _hp_of(defender)))
	var def_max := _max_hp_of(defender)
	_defender_name.text = _name_of(defender)
	_defender_bar.max_value = maxi(1, def_max)
	_defender_bar.value = clampi(target_hp, 0, maxi(1, def_max))
	_defender_hp.text = "%d/%d" % [target_hp, def_max]

	if _move_has_damage(move):
		var hit_pct: float = float(preview.get("hit_pct", 100.0))
		var crit_pct: float = float(preview.get("crit_pct", 0.0))
		var dmg: int = int(preview.get("damage", 0))
		var crit_dmg: int = int(preview.get("crit_damage", dmg))
		var remaining: int = int(preview.get("remaining", target_hp))
		var lethal: bool = bool(preview.get("lethal", false))

		_hit_value.text = "%d%%" % int(round(hit_pct))

		var dmg_text := str(dmg)
		if crit_pct > 0.0 and crit_dmg != dmg:
			dmg_text += " (%d crit)" % crit_dmg
		_dmg_value.text = dmg_text

		_crit_value.text = "%d%%" % int(round(crit_pct))
		_show_stat_row(_crit_value, crit_pct > 0.0)

		_result_value.text = "%d -> %d" % [target_hp, remaining]
		_show_stat_row(_result_value, true)
		_show_stat_row(_dmg_value, true)
		_show_stat_row(_hit_value, true)
		_lethal_label.visible = lethal
	else:
		# Pure heal/buff/tile move aimed here: keep it clean, no fake damage.
		_hit_value.text = "No damage"
		_show_stat_row(_hit_value, true)
		_show_stat_row(_dmg_value, false)
		_show_stat_row(_crit_value, false)
		_show_stat_row(_result_value, false)
		_lethal_label.visible = false

	_cover_viewport()
	_fit_to_viewport()
	visible = true

## Force this root to span the entire game window (regardless of the small sidebar
## parent), so the card's viewport-centred anchors are correct and it never lands
## off-screen. Top-left anchors + an explicit size, so no parent Container layout pass
## can shrink us back to the sidebar.
func _cover_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var r: Vector2 = vp.get_visible_rect().size
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = r

## Keep the card width within the viewport on small/narrow windows: it never exceeds
## CARD_WIDTH, but shrinks to fit when the screen is narrower than that plus a margin,
## so the damage prediction always fits fully on screen. Re-centres via the offsets.
func _fit_to_viewport() -> void:
	if _card == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vw: float = vp.get_visible_rect().size.x
	var margin: float = 24.0
	var w: float = minf(CARD_WIDTH, maxf(220.0, vw - margin * 2.0))
	_card.offset_left = -w * 0.5
	_card.offset_right = w * 0.5

func hide_forecast() -> void:
	"""Hide the forecast (targeting cancelled/cleared, or the move resolved)."""
	visible = false

# --- Helpers ----------------------------------------------------------------

func _show_stat_row(value_label: Label, shown: bool) -> void:
	"""Toggle a whole 'key: value' row via the value Label's parent HBox."""
	var row := value_label.get_parent()
	if row is Control:
		(row as Control).visible = shown

func _move_has_damage(move: MoveResource) -> bool:
	if move == null:
		return false
	for effect in move.effects:
		if effect is DamageEffect:
			return true
	return false

func _name_of(unit) -> String:
	if unit and unit.has_method("get_display_name"):
		return unit.get_display_name()
	return "?"

func _hp_of(unit) -> int:
	if unit == null:
		return 0
	if unit.has_method("get_hp"):
		return int(unit.get_hp())
	if unit.has_method("get_stat"):
		return int(unit.get_stat("health"))
	return 0

func _max_hp_of(unit) -> int:
	if unit and unit.has_method("get_stat"):
		var m: int = unit.get_stat("health")
		if m > 0:
			return m
	return maxi(1, _hp_of(unit))
