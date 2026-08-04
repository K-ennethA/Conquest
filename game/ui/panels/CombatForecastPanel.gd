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

const CARD_WIDTH := 360.0
## Distance from the TOP edge the card floats at. Sits just below the slim turn chip
## (~56px top bar), so it no longer overlaps the banner but still reliably renders
## (a bottom-anchored grow collapsed to zero height -- the "forecast is gone" bug).
const TOP_MARGIN := 70.0
## Distance from the LEFT edge the card floats at.
const SIDE_MARGIN := 16.0
## Panel background opacity so board units partly show through the card while aiming;
## kept high enough (0.9) that the forecast text stays fully readable.
const CARD_BG_ALPHA := 0.9

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
## "3 → 5" -- shown ONLY while something is extending the attacker's reach for this move.
## A forecast that always printed a Range row would spend a line of a 720p card on a
## number the player already knows from the highlighted tiles; a row that appears exactly
## when the reach is NOT the authored one is a signal instead of furniture.
var _range_value: Label
## "Strong ×1.5" / "Resisted ×0.75" -- the element matchup, shown ONLY when it is not
## neutral. Same rule as the Range row above and for the same reason: the overwhelmingly
## common matchup is ×1.0, and a card that spends a line of a 720p budget printing
## "Neutral ×1" on every aim has turned a signal into furniture. The damage NUMBER already
## has the multiplier folded in -- this row names WHY it is what it is.
var _type_value: Label
## "+30% (Grass Cutter)" -- what an ability is doing to this specific hit, shown only when
## some ability is doing something. Read out of the preview's `ability_bonus_percent` /
## `ability_notes`, so this panel enumerates no abilities of its own.
var _ability_value: Label
## "absorbs 12 (3 left)" -- shown ONLY when the TARGET is carrying a damage-soak shield.
## Same "silent on the common case" rule as the Type / Range / Ability rows: almost nobody
## is shielded, and a card that printed "Shield 0" on every aim would have turned a signal
## into furniture.
##
## The split is [method Unit.absorb_split] -- the same function [method Unit.take_damage]
## burns the shield with -- reached through [method ShieldVisuals.absorb_text]. This panel
## does no absorption arithmetic of its own, so the line it prints and the soak the board
## performs cannot drift (CONQUEST.md rule 9).
var _shield_value: Label
var _result_value: Label
var _lethal_label: Label
## FE-style HP preview: a red rect over the DEFENDER bar covering exactly the chunk
## that would be lost (remaining -> current HP), pulsing so it flashes.
var _dmg_preview: ColorRect
var _flash_tween: Tween

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
	# the player can see the units being targeted, clear of the top-center turn banner and
	# the right-edge sidebar. Grows DOWNWARD (and rightward) from the top-left margin to fit
	# its content, so it can never collapse to zero height / slide off-screen.
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
	# Red "about to be lost" overlay, anchored to a fraction of the bar (set per forecast).
	_dmg_preview = ColorRect.new()
	_dmg_preview.name = "DamagePreview"
	_dmg_preview.color = Color(1.0, 0.22, 0.16, 0.9)
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
	# The breakdown sits DIRECTLY under the number it explains, and both rows default to
	# hidden -- a neutral, ability-free hit renders exactly the card that shipped before.
	_type_value = _add_stat_row(stats_vb, "Type")
	_show_stat_row(_type_value, false)
	_ability_value = _add_stat_row(stats_vb, "Ability")
	_show_stat_row(_ability_value, false)
	_crit_value = _add_stat_row(stats_vb, "Crit")
	_range_value = _add_stat_row(stats_vb, "Range")
	_show_stat_row(_range_value, false)
	# Between the damage rows and the HP outcome, because that is where it happens: the
	# shield is what stands between the number above it and the health below it.
	_shield_value = _add_stat_row(stats_vb, "Shield")
	_show_stat_row(_shield_value, false)
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

	# Make the amber card slightly translucent so board units partly show through it while
	# aiming (secondary to the top-left move above; text stays fully readable at 0.9).
	var card_box: StyleBox = _card.get_theme_stylebox("panel")
	if card_box is StyleBoxFlat:
		var translucent: StyleBoxFlat = (card_box as StyleBoxFlat).duplicate()
		translucent.bg_color.a = CARD_BG_ALPHA
		_card.add_theme_stylebox_override("panel", translucent)

	# Dark inset plate behind the exchange stats, cream text so it reads on it.
	plate.add_theme_stylebox_override("panel", ConquestTheme.plate_box())
	for lbl in [_hit_value, _dmg_value, _crit_value, _range_value, _result_value,
			_type_value, _ability_value, _shield_value]:
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

# --- The preview source (the one seam) ---------------------------------------

## Where the forecast's numbers come from. Empty by default, meaning
## [method MoveExecutor.preview_vs] -- the production path, unchanged.
##
## THE ONE SEAM, deliberately singular. Every number this card renders arrives in ONE
## dictionary from ONE call, so a test can hand it a stubbed matchup (or a future combat
## change can move where the dictionary is built) without this file learning anything new
## about combat. Set it with [method set_preview_source]; the callable takes
## `(move, attacker, defender, board)` and returns the preview dictionary.
var _preview_source: Callable = Callable()


## Point the card at a different preview producer. Pass an empty [Callable] to restore
## the production one. Used by the forecast suites to render a decided matchup without
## authoring a chart entry, and by any future relocation of the previewer.
func set_preview_source(source: Callable) -> void:
	_preview_source = source


## The preview dictionary for this aim. Shape (keys read defensively, so a producer that
## does not carry the newer ones simply renders the card that shipped before):
##
##   total / damage, base, hit_pct, crit_pct, crit_damage, target_hp, remaining, lethal,
##   element_mult: float, element_label: StringName,
##   ability_bonus_percent: int, ability_notes: Array[String]
func _preview_for(move, attacker, defender, board = null) -> Dictionary:
	if _preview_source.is_valid():
		var out = _preview_source.call(move, attacker, defender, board)
		return out if out is Dictionary else {}
	return MoveExecutor.preview_vs(move, attacker, defender, board)


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

	# Boosted reach: the ONE stat on this card whose live value can differ from the move's
	# authored one without anything else on screen saying so. Read through
	# MoveResource.effective_max_range (via MoveStatVisuals) -- the same helper the
	# executor validates casts with -- so the forecast can never advertise a reach the
	# cast would then reject. Hidden entirely when the reach is unmodified.
	var range_dict: Dictionary = MoveStatVisuals.range_info(move, attacker)
	if bool(range_dict.get("modified", false)):
		_range_value.text = "%d → %d" % [
			int(range_dict.get("base", 0)), int(range_dict.get("effective", 0))]
		_range_value.add_theme_color_override(
			"font_color", range_dict.get("color", ConquestTheme.CREAM))
		_show_stat_row(_range_value, true)
	else:
		_show_stat_row(_range_value, false)

	var preview: Dictionary = _preview_for(move, attacker, defender)

	# Defender column.
	var target_hp: int = int(preview.get("target_hp", _hp_of(defender)))
	var def_max := _max_hp_of(defender)
	_defender_name.text = _name_of(defender)
	_defender_bar.max_value = maxi(1, def_max)
	_defender_bar.value = clampi(target_hp, 0, maxi(1, def_max))
	_defender_hp.text = "%d/%d" % [target_hp, def_max]

	if _move_has_damage(move, attacker):
		var hit_pct: float = float(preview.get("hit_pct", 100.0))
		var crit_pct: float = float(preview.get("crit_pct", 0.0))
		# "total" is the previewer's post-everything number (the contract the breakdown
		# rows below are the explanation OF); "damage" is what the shipped previewer calls
		# the same thing. Preferring total means the card follows the number the combat
		# side declares final, and falls back cleanly while only one of the two exists.
		var dmg: int = int(preview.get("total", preview.get("damage", 0)))
		var crit_dmg: int = int(preview.get("crit_damage", dmg))
		var remaining: int = int(preview.get("remaining", target_hp))
		var lethal: bool = bool(preview.get("lethal", false))

		_hit_value.text = "%d%%" % int(round(hit_pct))

		var dmg_text := str(dmg)
		if crit_pct > 0.0 and crit_dmg != dmg:
			dmg_text += " (%d crit)" % crit_dmg
		# A buffed / debuffed ATTACK stat is already folded into `dmg` by the previewer,
		# so the number is right -- but silently right. The delta names the reason, read
		# off the unit's own effective-vs-base pair so any source (status, item, tile,
		# augment) shows up without this panel enumerating them.
		var atk: Dictionary = MoveStatVisuals.stat_info(attacker, "attack", "Attack")
		if bool(atk.get("modified", false)):
			dmg_text += String(atk.get("suffix", ""))
			_dmg_value.add_theme_color_override(
				"font_color", atk.get("color", ConquestTheme.HIT_ORANGE))
		else:
			_dmg_value.add_theme_color_override("font_color", ConquestTheme.HIT_ORANGE)
		_dmg_value.text = dmg_text

		_update_breakdown_rows(preview, move, defender)
		_update_shield_row(defender, dmg)

		_crit_value.text = "%d%%" % int(round(crit_pct))
		_show_stat_row(_crit_value, crit_pct > 0.0)

		_result_value.text = "%d -> %d" % [target_hp, remaining]
		_show_stat_row(_result_value, true)
		_show_stat_row(_dmg_value, true)
		_show_stat_row(_hit_value, true)
		_lethal_label.visible = lethal
		_show_damage_preview(remaining, target_hp, maxi(1, def_max))
	else:
		# Pure heal/buff/tile move aimed here: keep it clean, no fake damage.
		_hit_value.text = "No damage"
		_show_stat_row(_hit_value, true)
		_show_stat_row(_dmg_value, false)
		_show_stat_row(_crit_value, false)
		_show_stat_row(_result_value, false)
		# A heal or a buff has no matchup and no damage for an ability to modify, so the
		# breakdown rows go with the damage rows they explain.
		_show_stat_row(_type_value, false)
		_show_stat_row(_ability_value, false)
		# Nothing to absorb: a heal or a buff never reaches the target's shield.
		_show_stat_row(_shield_value, false)
		_lethal_label.visible = false
		_hide_damage_preview()

	_cover_viewport()
	_fit_to_viewport()
	visible = true

## Explain the damage number: the element matchup, and whatever an ability is adding to
## or taking off this particular hit.
##
## BOTH ROWS ARE SILENT ON THE COMMON CASE. A neutral matchup renders no Type row and a
## 0% ability bonus renders no Ability row -- so most aims cost the card exactly the
## height it had before, and a row APPEARING is itself the information. The words and
## colours come from [ElementVisuals], which is also what puts the element badge on the
## unit card, so "green means this hit is better for me" is one rule across the HUD.
##
## HEIGHT BUDGET. The card is TOP-anchored at [constant TOP_MARGIN] (70) with
## GROW_DIRECTION_END and no fixed height -- its "flexible region" is the whole card, and
## these two rows are absorbed by it. The arithmetic at 720p: the card's content is the
## 4px stripe + a ~22px title + a ~51px combatant row + the stats plate, at 6px
## separation, and the plate holds up to EIGHT ~19px rows at 3px separation (Hit, Damage,
## Type, Ability, Crit, Range, Shield, HP) plus the LETHAL line -- so a fully-populated
## card is ~312px and its bottom edge lands at 70 + 312 == 382, comfortably above half the
## 720px window. These rows add ~22px each to a worst case that has ~360px of headroom.
## `test_battle_element_readout.gd` and `test_shield_readout_live.gd` measure the real rect
## rather than trusting this comment.
func _update_breakdown_rows(preview: Dictionary, move, defender) -> void:
	# The multiplier is the previewer's to decide -- this card only renders it. The
	# fallback exists so the rows are correct against a previewer that has not yet started
	# publishing them, and it asks the SAME helper the executor scales damage with, so the
	# fallback can never disagree with the number printed above it.
	var mult: float = float(preview.get("element_mult", _fallback_element_mult(move, defender)))
	var label = preview.get("element_label", null)
	var matchup: String = ElementVisuals.effectiveness_text(mult, label)
	if matchup == "":
		_show_stat_row(_type_value, false)
	else:
		if label == null:
			label = ElementVisuals.label_for_multiplier(mult)
		_type_value.text = matchup
		_type_value.add_theme_color_override(
				"font_color", ElementVisuals.effectiveness_color(label))
		_show_stat_row(_type_value, true)

	var percent: int = int(preview.get("ability_bonus_percent", 0))
	var ability: String = ElementVisuals.ability_bonus_text(
			percent, preview.get("ability_notes", null))
	if ability == "":
		_show_stat_row(_ability_value, false)
	else:
		_ability_value.text = ability
		_ability_value.add_theme_color_override(
				"font_color", ElementVisuals.ability_bonus_color(percent))
		_show_stat_row(_ability_value, true)


## Make a shielded target's absorption legible: "Shield  absorbs 12 (3 left)".
##
## SCOPE, deliberately narrow. The Damage number and the HP outcome above/below keep
## exactly the meaning they always had -- they are the previewer's, and the previewer does
## not model the shield -- so this row is ADDITIVE: it says how much of that damage the
## ward will eat, and what is left of the ward afterwards. Nothing else on the card moves.
##
## The arithmetic is [method Unit.absorb_split] via [method ShieldVisuals.absorb_text], the
## same function the live hit uses. Hidden whenever the target has no shield, which is
## almost always.
func _update_shield_row(defender, damage: int) -> void:
	if _shield_value == null:
		return
	var text: String = ShieldVisuals.absorb_text(ShieldVisuals.shield_of(defender), damage)
	if text == "":
		_show_stat_row(_shield_value, false)
		return
	_shield_value.text = text
	_shield_value.add_theme_color_override("font_color", ShieldVisuals.SILVER)
	_show_stat_row(_shield_value, true)


## The element multiplier for this hit when the preview did not carry one.
##
## [method ElementChart.damage_scale_for] is the single entry point both
## [method DamageEffect.apply] and the previewer scale damage through, so reading it here
## gives the row the same verdict the hit will have -- never a re-derivation. Null board:
## the chart resolves the live one itself, and fails to NEUTRAL when there is none.
func _fallback_element_mult(move, defender) -> float:
	if move == null or defender == null:
		return 1.0
	return ElementChart.damage_scale_for(move, defender, null)


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

func hide_forecast() -> void:
	"""Hide the forecast (targeting cancelled/cleared, or the move resolved)."""
	_hide_damage_preview()
	visible = false

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
