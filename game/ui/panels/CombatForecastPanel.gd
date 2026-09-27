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
# Positioned in the TOP-LEFT corner (not dead-center) so the middle of the board stays
# visible while the player aims -- the centered card used to sit right over the enemies
# being targeted. Top-left is used instead of top-right (gear button + right sidebar) or
# the bottom corners (terrain/turn/hover readouts). The card stays TOP-anchored with an
# END grow so it can never collapse to zero height (the old "forecast is gone" bug that
# forced the move off the bottom edge in the first place).

const CARD_WIDTH := 420.0
## Minimum distance from the TOP edge the card floats at. The card is pushed further
## down to clear the Battle Log (top-left, see _top_offset) so the two never overlap.
const TOP_MARGIN := HudSafeArea.TOP_RESERVE
## Distance from the LEFT edge the card floats at.
const SIDE_MARGIN := ConquestTheme.MARGIN
## Panel background opacity so board units partly show through the card while aiming;
## kept high enough (0.9) that the forecast text stays fully readable.
const CARD_BG_ALPHA := 0.95

# --- Node references (built once in _ready, only re-populated in show_forecast) --
var _card: PanelContainer
var _element_stripe: GroveGem
var _card_sb: OrnateStyleBox
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
## FE-style HP preview: a red rect over the DEFENDER bar covering exactly the chunk
## that would be lost (remaining -> current HP), pulsing so it flashes.
var _dmg_preview: ColorRect
var _flash_tween: Tween
## Modifier chips under the title: type matchup (ElementChart) and height (Elevation).
var _chip_row: HBoxContainer
var _type_chip: Label
var _height_chip: Label
var _move_label: Label
var _attacker_portrait: PanelContainer
var _defender_portrait: PanelContainer
var _crit_dmg_label: Label
## The two units currently forecast (see shows_unit).
var _shown_attacker = null
var _shown_defender = null

const CHIP_GOOD := Color("7be07a")
const CHIP_BAD := Color("ff8a78")

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
	# The floating card, anchored to the TOP-LEFT of the viewport: off the board centre so
	# the player can see the units being targeted, clear of the top-center phase chip and
	# the right-edge command menu. Grows DOWNWARD from its top edge (never collapses).
	_card = PanelContainer.new()
	_card.name = "ForecastCard"
	_card.anchor_left = 0.0
	_card.anchor_right = 0.0
	_card.anchor_top = 0.0
	_card.anchor_bottom = 0.0
	_card.grow_horizontal = Control.GROW_DIRECTION_END
	_card.grow_vertical = Control.GROW_DIRECTION_END
	_card.offset_left = SIDE_MARGIN
	_card.offset_right = SIDE_MARGIN + CARD_WIDTH
	_card.offset_top = TOP_MARGIN
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 8)
	root_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(root_vb)

	# Title row: gold section tag + the move being used (element-coloured stripe).
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(title_row)
	var title := ConquestTheme.section_label("Battle Forecast")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(title)
	_element_stripe = GroveGem.new()
	_element_stripe.color = ConquestTheme.GOLD
	_element_stripe.custom_minimum_size = Vector2(15, 19)
	_element_stripe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_element_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_element_stripe)
	_move_label = Label.new()
	_move_label.name = "MoveLabel"
	_move_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_move_label)

	# Attacker | vs | Defender.
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 10)
	sides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(sides)

	var attacker_col := _build_side(false)
	_attacker_name = attacker_col["name"]
	_attacker_bar = attacker_col["bar"]
	_attacker_hp = attacker_col["hp"]
	_attacker_portrait = attacker_col["portrait"]
	attacker_col["root"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.add_child(attacker_col["root"])

	var vs := Label.new()
	vs.text = "VS"
	vs.theme_type_variation = &"SectionLabel"
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sides.add_child(vs)

	var defender_col := _build_side(true)
	_defender_name = defender_col["name"]
	_defender_bar = defender_col["bar"]
	_defender_hp = defender_col["hp"]
	_defender_portrait = defender_col["portrait"]
	# Red "about to be lost" overlay, anchored to a fraction of the bar (set per forecast).
	_dmg_preview = ColorRect.new()
	_dmg_preview.name = "DamagePreview"
	_dmg_preview.color = ConquestTheme.HP_LOSS
	_dmg_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg_preview.anchor_top = 0.0
	_dmg_preview.anchor_bottom = 1.0
	_dmg_preview.offset_left = 0.0
	_dmg_preview.offset_right = 0.0
	_dmg_preview.offset_top = 0.0
	_dmg_preview.offset_bottom = 0.0
	_dmg_preview.visible = false
	_defender_bar.add_child(_dmg_preview)  # children draw over the bar fill
	defender_col["root"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.add_child(defender_col["root"])

	# Matchup chips ("▲ Effective" / "▼ Resisted", "▲ High ground" / "▼ Low ground"),
	# shown only when they apply.
	_chip_row = HBoxContainer.new()
	_chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_chip_row.add_theme_constant_override("separation", 8)
	_chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_chip_row)
	_type_chip = _make_chip()
	_chip_row.add_child(_type_chip)
	_height_chip = _make_chip()
	_chip_row.add_child(_height_chip)

	# Big numbers plate: DMG | HIT | CRIT (+ the HP result row kept for callers).
	var plate := PanelContainer.new()
	plate.name = "StatsPlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(plate)

	var stats_vb := VBoxContainer.new()
	stats_vb.add_theme_constant_override("separation", 4)
	stats_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(stats_vb)

	var big := HBoxContainer.new()
	big.name = "BigNumbers"
	big.add_theme_constant_override("separation", 4)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_vb.add_child(big)
	_dmg_value = _add_big_stat(big, "Damage")
	_hit_value = _add_big_stat(big, "Hit")
	_crit_value = _add_big_stat(big, "Crit")
	_crit_dmg_label = Label.new()
	_crit_dmg_label.name = "CritDamage"
	_crit_dmg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crit_dmg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg_value.get_parent().add_child(_crit_dmg_label)

	_result_value = _add_stat_row(stats_vb, "Target HP")

	_lethal_label = Label.new()
	_lethal_label.text = "LETHAL"
	_lethal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lethal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lethal_label.visible = false
	root_vb.add_child(_lethal_label)

	# HUD theme FIRST (it strips baked-in colours / per-panel styleboxes), THEN our
	# deliberate local plate + text overrides so they survive.
	ConquestTheme.apply_to(self)

	var card_sb := ConquestTheme.panel_box(CARD_BG_ALPHA)
	card_sb.border_color = ConquestTheme.GOLD_DK
	card_sb.content_margin_top = 12
	card_sb.content_margin_bottom = 14
	card_sb.crest = true
	# Attacker's team on the left edge, defender's on the right (set per forecast).
	card_sb.accent_side = SIDE_LEFT
	card_sb.accent_width = 4.0
	_card_sb = card_sb
	_card.add_theme_stylebox_override("panel", card_sb)
	plate.add_theme_stylebox_override("panel", ConquestTheme.plate_box())

	_move_label.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
	_move_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	for lbl in [_attacker_name, _defender_name]:
		lbl.add_theme_color_override("font_color", ConquestTheme.CREAM)
	for lbl in [_attacker_hp, _defender_hp]:
		lbl.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
		lbl.add_theme_color_override("font_color", ConquestTheme.CREAM)
	for lbl in [_dmg_value, _hit_value, _crit_value]:
		lbl.add_theme_font_override("font", MenuTheme.bold_font(0.6))
		lbl.add_theme_font_size_override("font_size", ConquestTheme.FS_BIG_NUMBER)
	_dmg_value.add_theme_color_override("font_color", ConquestTheme.DMG_COLOR)
	_hit_value.add_theme_color_override("font_color", ConquestTheme.HIT_COLOR)
	_crit_value.add_theme_color_override("font_color", ConquestTheme.CRIT_COLOR)
	_crit_dmg_label.add_theme_font_size_override("font_size", ConquestTheme.FS_CAPTION)
	_crit_dmg_label.add_theme_color_override("font_color", ConquestTheme.CRIT_COLOR)
	_result_value.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
	_result_value.add_theme_color_override("font_color", ConquestTheme.CREAM)
	for row in stats_vb.get_children():
		if row is HBoxContainer and row.name != "BigNumbers":
			for child in row.get_children():
				if child is Label and child != _result_value:
					child.add_theme_color_override("font_color", ConquestTheme.TEXT_DIM)
					child.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	_lethal_label.add_theme_font_override("font", MenuTheme.display_font(4))
	_lethal_label.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
	_lethal_label.add_theme_color_override("font_color", ConquestTheme.INK)
	var lethal_sb := MenuTheme.box(ConquestTheme.DANGER, ConquestTheme.DANGER.lightened(0.3), 1, 8, 12, 4)
	_lethal_label.add_theme_stylebox_override("normal", lethal_sb)

func _make_chip() -> Label:
	# Bright text on a small dark plate so it reads on the amber card.
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	return l

## Matchup chip texts for [param attacker] using [param move] on [param defender]:
## { "type": "" | "▲ Effective" | "▼ Resisted", "type_good": bool,
##   "height": "" | "▲ High ground" | "▼ Low ground", "height_good": bool }.
## Static + pure so it is unit-testable without building the panel.
static func matchup_chips(attacker, defender, move, board) -> Dictionary:
	var out := { "type": "", "type_good": true, "height": "", "height_good": true }
	var mult: float = ElementChart.type_scale_for(move, defender)
	if mult > 1.001:
		out["type"] = "▲ Effective"
		out["type_good"] = true
	elif mult < 0.999:
		out["type"] = "▼ Resisted"
		out["type_good"] = false
	if board != null and board.has_method("cell_of") and attacker != null and defender != null:
		var adv := Elevation.advantage(board.cell_of(attacker), board.cell_of(defender))
		if adv > 0:
			out["height"] = "▲ High ground"
			out["height_good"] = true
		elif adv < 0:
			out["height"] = "▼ Low ground"
			out["height_good"] = false
	return out

func _apply_chips(attacker, defender, move, board) -> void:
	var chips := matchup_chips(attacker, defender, move, board)
	_set_chip(_type_chip, chips["type"], chips["type_good"])
	_set_chip(_height_chip, chips["height"], chips["height_good"])
	_chip_row.visible = _type_chip.visible or _height_chip.visible

func _set_chip(chip: Label, text: String, good: bool) -> void:
	# (Styled here, after ConquestTheme.apply_to has swept the card's overrides.)
	var col := CHIP_GOOD if good else CHIP_BAD
	chip.add_theme_stylebox_override("normal", ConquestTheme.chip_style(col))
	chip.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	chip.text = text
	chip.visible = text != ""
	chip.add_theme_color_override("font_color", col.lightened(0.3))

func _build_side(defender: bool) -> Dictionary:
	"""One combatant column: portrait + name, HP bar, 'current/max' (defender:
	'current -> remaining'). The defender column mirrors the attacker's (portrait
	on the right) so the two face each other like FE's forecast."""
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.alignment = BoxContainer.ALIGNMENT_END if defender else BoxContainer.ALIGNMENT_BEGIN
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(head)
	var portrait := ConquestTheme.portrait("?", ConquestTheme.GOLD, ConquestTheme.BORDER, 38.0)
	var name_lbl := Label.new()
	name_lbl.text = "-"
	name_lbl.theme_type_variation = &"SubheadingLabel"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if defender else HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.clip_text = true
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.custom_minimum_size = Vector2(60, 0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if defender:
		head.add_child(name_lbl)
		head.add_child(portrait)
	else:
		head.add_child(portrait)
		head.add_child(name_lbl)

	var bar := ConquestTheme.hp_bar(12.0)
	bar.custom_minimum_size = Vector2(150, 12)
	vb.add_child(bar)

	var hp_lbl := Label.new()
	hp_lbl.text = "-/-"
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if defender else HORIZONTAL_ALIGNMENT_LEFT
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hp_lbl)

	return {"root": vb, "name": name_lbl, "bar": bar, "hp": hp_lbl, "portrait": portrait}


## One big-number column ("DAMAGE" caption over a large value). Returns the value.
func _add_big_stat(parent: HBoxContainer, caption: String) -> Label:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", -4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := ConquestTheme.section_label(caption)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	var value := Label.new()
	value.text = "-"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(value)
	parent.add_child(col)
	return value

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

func show_forecast(attacker, defender, move: MoveResource, board = null) -> void:
	"""Populate the forecast for `attacker` using `move` against `defender`, then
	show it. Non-mutating: reads MoveExecutor.preview_vs() only. No-op (hides) on
	missing arguments. Pass the live `board` so terrain / height / board-gated
	passives match resolution (null falls back to CombatServices' board)."""
	if attacker == null or defender == null or move == null:
		hide_forecast()
		return
	_shown_attacker = attacker
	_shown_defender = defender
	if _card_sb != null:
		_card_sb.accent_color = ConquestTheme.team_color(ConquestTheme.owner_of(attacker))
		_card_sb.accent_color_2 = ConquestTheme.team_color(ConquestTheme.owner_of(defender))
		_card_sb.emit_changed()

	# Attacker column.
	_attacker_name.text = _name_of(attacker)
	var att_hp := _hp_of(attacker)
	var att_max := _max_hp_of(attacker)
	_attacker_bar.max_value = maxi(1, att_max)
	_attacker_bar.value = clampi(att_hp, 0, maxi(1, att_max))
	ConquestTheme.tint_hp_bar(_attacker_bar, float(att_hp) / float(maxi(1, att_max)))
	_attacker_hp.text = "%d/%d" % [att_hp, att_max]
	_set_portrait(_attacker_portrait, attacker)

	# Move name + element accent stripe.
	_element_stripe.color = ConquestTheme.element_color(String(move.element))
	_move_label.text = move.display_name_for(attacker) if move.has_method("display_name_for") else move.display_name

	if board == null:
		board = MoveExecutor._live_board()
	var preview: Dictionary = MoveExecutor.preview_vs(move, attacker, defender, board)
	_apply_chips(attacker, defender, move, board)

	# Defender column.
	var target_hp: int = int(preview.get("target_hp", _hp_of(defender)))
	var def_max := _max_hp_of(defender)
	_defender_name.text = _name_of(defender)
	_defender_bar.max_value = maxi(1, def_max)
	_defender_bar.value = clampi(target_hp, 0, maxi(1, def_max))
	ConquestTheme.tint_hp_bar(_defender_bar, float(target_hp) / float(maxi(1, def_max)))
	_defender_hp.text = "%d/%d" % [target_hp, def_max]
	_set_portrait(_defender_portrait, defender)

	if _move_has_damage(move, attacker):
		var hit_pct: float = float(preview.get("hit_pct", 100.0))
		var crit_pct: float = float(preview.get("crit_pct", 0.0))
		var dmg: int = int(preview.get("damage", 0))
		var crit_dmg: int = int(preview.get("crit_damage", dmg))
		var remaining: int = int(preview.get("remaining", target_hp))
		var lethal: bool = bool(preview.get("lethal", false))

		_hit_value.text = "%d%%" % int(round(hit_pct))

		_dmg_value.text = str(dmg)
		_crit_dmg_label.text = "%d on crit" % crit_dmg if crit_pct > 0.0 and crit_dmg != dmg else ""
		_crit_dmg_label.visible = _crit_dmg_label.text != ""

		_crit_value.text = "%d%%" % int(round(crit_pct))
		_show_stat_row(_crit_value, true)

		_result_value.text = "%d  →  %d" % [target_hp, remaining]
		_defender_hp.text = "%d → %d" % [target_hp, remaining]
		# The defender column already reads "55 → 23"; the legacy HP row stays
		# populated (callers / tests read it) but hidden to avoid saying it twice.
		_show_stat_row(_result_value, false)
		_show_stat_row(_dmg_value, true)
		_show_stat_row(_hit_value, true)
		_lethal_label.visible = lethal
		_show_damage_preview(remaining, target_hp, maxi(1, def_max))
	else:
		# Pure heal/buff/tile move aimed here: keep it clean, no fake damage.
		_hit_value.text = "—"
		_crit_dmg_label.visible = false
		_show_stat_row(_hit_value, true)
		_show_stat_row(_dmg_value, false)
		_show_stat_row(_crit_value, false)
		_show_stat_row(_result_value, false)
		_lethal_label.visible = false
		_hide_damage_preview()

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
	var w: float = minf(CARD_WIDTH, maxf(220.0, vw - SIDE_MARGIN * 2.0))
	# Top-left anchored: pin the left edge at the margin and size the width to the right.
	_card.offset_left = SIDE_MARGIN
	_card.offset_right = SIDE_MARGIN + w
	_card.offset_top = _top_offset()


## Top edge for the card: just under the top-left HUD stack (Battle Log -- taller
## when expanded -- and the Arena run panel) so they never overlap.
func _top_offset() -> float:
	var top := TOP_MARGIN
	if not is_inside_tree():
		return top
	for n in get_tree().get_nodes_in_group("hud_top_left"):
		var c := n as Control
		if c != null and c.is_visible_in_tree():
			top = maxf(top, c.get_global_rect().end.y + 10.0)
	return top

func hide_forecast() -> void:
	"""Hide the forecast (targeting cancelled/cleared, or the move resolved)."""
	_hide_damage_preview()
	visible = false
	_shown_attacker = null
	_shown_defender = null


## True while the forecast is up and [param unit] is one of its two sides (the hover
## card uses this to avoid repeating a unit already on screen).
func shows_unit(unit) -> bool:
	return visible and unit != null and (unit == _shown_attacker or unit == _shown_defender)

# --- Damage preview (FE-style flashing red HP chunk) ------------------------

## Overlay the red "about to be lost" band on the defender bar, from `remaining` to
## `current` HP as a fraction of the bar, and flash it.
func _show_damage_preview(remaining: int, current: int, hp_max: int) -> void:
	if _dmg_preview == null:
		return
	var lost: int = current - remaining
	if lost <= 0 or hp_max <= 0:
		_hide_damage_preview()
		return
	_dmg_preview.anchor_left = clampf(float(remaining) / float(hp_max), 0.0, 1.0)
	_dmg_preview.anchor_right = clampf(float(current) / float(hp_max), 0.0, 1.0)
	_dmg_preview.offset_left = 0.0
	_dmg_preview.offset_right = 0.0
	_dmg_preview.visible = true
	_dmg_preview.modulate.a = 1.0
	_start_damage_flash()

func _hide_damage_preview() -> void:
	_stop_damage_flash()
	if _dmg_preview != null:
		_dmg_preview.visible = false

## Pulse the red band so it clearly reads as a warning. Honors the animations toggle:
## when animations are off it just stays solid red (still shows the chunk, no motion).
func _start_damage_flash() -> void:
	_stop_damage_flash()
	if _dmg_preview == null:
		return
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null \
			and GameSettings.has_method("animations_on") and not GameSettings.animations_on():
		_dmg_preview.modulate.a = 1.0
		return
	_flash_tween = create_tween().set_loops()
	_flash_tween.tween_property(_dmg_preview, "modulate:a", 0.35, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flash_tween.tween_property(_dmg_preview, "modulate:a", 1.0, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_damage_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	if _dmg_preview != null:
		_dmg_preview.modulate.a = 1.0

# --- Helpers ----------------------------------------------------------------

func _show_stat_row(value_label: Label, shown: bool) -> void:
	"""Toggle a whole 'key: value' row via the value Label's parent HBox."""
	var row := value_label.get_parent()
	if row is Control:
		(row as Control).visible = shown

func _move_has_damage(move: MoveResource, caster = null) -> bool:
	if move == null:
		return false
	# Mode-aware, so the forecast reads the mode actually in force for this caster (a
	# two-mode move's armed-release damage would otherwise be invisible).
	for effect in move.effects_for(caster):
		if effect is DamageEffect:
			return true
	return false

func _set_portrait(p: PanelContainer, unit) -> void:
	if p == null or unit == null:
		return
	var cols := ConquestTheme.unit_portrait_colors(unit)
	ConquestTheme.set_portrait(p, _name_of(unit), cols[0], cols[1])


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
