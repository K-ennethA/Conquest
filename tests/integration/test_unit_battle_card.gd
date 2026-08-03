extends GutTest

## The COMPACT BATTLE CARD's content contract ([UnitInfoPanel]).
##
## The card was cut down from a full unit sheet to exactly the battle-relevant facts,
## because all three of the reported problems came from it trying to be two surfaces at
## once: the Abilities section was always the one that got cut off, its stats duplicated
## the right sidebar's "Unit Summary" dropdown, and it showed far too much at a glance for
## something that is on screen the whole time the player is aiming at the map.
##
## So this suite pins what the card MUST show, what it MUST NOT show, and -- the part that
## is easy to get wrong -- that the four stat chips report EFFECTIVE values read through
## the same helpers gameplay uses, not authored bases and not numbers re-derived here.
##
## Builds the real UnitInfoPanel.tscn and drives real Units, so it is an integration test
## by tests/README's split.

const INFO_PANEL := preload("res://game/ui/panels/UnitInfoPanel.tscn")


func _make_character() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"vineweave"
	c.display_name = "Torvald"
	c.base_health = 40
	c.base_attack = 20
	c.base_defense = 15
	c.base_speed = 12
	c.base_movement = 3
	return c


func _make_unit() -> Unit:
	var u := Unit.new()
	u.character_resource = _make_character()
	add_child_autofree(u)  # _ready derives the stats component AND the status controller
	return u


func _make_card() -> Control:
	var panel: Control = INFO_PANEL.instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame
	return panel


## The text on the ATK / DEF / SPD / MOV chip, or "" when that chip is missing.
func _chip_text(panel: Control, label: String) -> String:
	var row: Control = panel._stat_row
	if row == null:
		return ""
	var chip := row.get_node_or_null("StatChip" + label)
	if chip == null:
		return ""
	var value := chip.get_node_or_null("Value") as Label
	return value.text if value != null else ""


func _status_chip_texts(panel: Control) -> Array:
	var out: Array = []
	if panel._status_flow == null:
		return out
	for child in panel._status_flow.get_children():
		var label := child.get_node_or_null("ChipLabel") as Label
		if label != null:
			out.append(label.text)
	return out


func _condition(id: StringName, name_text: String, turns: int) -> StatusCondition:
	var c := StatusCondition.new()
	c.id = id
	c.display_name = name_text
	c.duration_turns = turns
	return c


# --- The four stat chips -------------------------------------------------------

func test_the_card_shows_exactly_four_stat_chips() -> void:
	var panel: Control = await _make_card()
	panel._on_unit_selected(_make_unit(), Vector3.ZERO)
	await get_tree().process_frame

	assert_eq(panel._stat_row.get_child_count(), 4,
			"one row, four chips -- ATK, DEF, SPD, MOV and nothing else")
	for label in ["ATK", "DEF", "SPD", "MOV"]:
		assert_ne(_chip_text(panel, label), "", "the %s chip is present" % label)


func test_an_unmodified_chip_reads_the_plain_stat_with_no_decoration() -> void:
	var panel: Control = await _make_card()
	var unit := _make_unit()
	panel._on_unit_selected(unit, Vector3.ZERO)
	await get_tree().process_frame

	assert_eq(_chip_text(panel, "ATK"), "ATK %d" % unit.get_stat("attack"),
			"a stat sitting at its base is printed bare -- no arrow, nothing to explain")
	assert_false(_chip_text(panel, "ATK").contains(MoveStatVisuals.UP_ARROW),
			"and carries no up arrow")
	assert_false(_chip_text(panel, "ATK").contains(MoveStatVisuals.DOWN_ARROW),
			"and no down arrow either")


func test_a_buffed_chip_shows_the_effective_value_and_an_up_arrow() -> void:
	var panel: Control = await _make_card()
	var unit := _make_unit()
	var base: int = unit.get_base_stat("attack")
	unit.add_stat_modifier("attack", 6, -1)

	panel._on_unit_selected(unit, Vector3.ZERO)
	await get_tree().process_frame

	assert_eq(unit.get_stat("attack"), base + 6, "the buff landed on the unit")
	assert_eq(_chip_text(panel, "ATK"), "ATK %d%s" % [base + 6, MoveStatVisuals.UP_ARROW],
			"the chip reports the EFFECTIVE attack, marked as raised")


func test_a_debuffed_chip_shows_the_effective_value_and_a_down_arrow() -> void:
	var panel: Control = await _make_card()
	var unit := _make_unit()
	var base: int = unit.get_base_stat("movement")
	unit.add_stat_modifier("movement", -2, -1)

	panel._on_unit_selected(unit, Vector3.ZERO)
	await get_tree().process_frame

	assert_eq(_chip_text(panel, "MOV"), "MOV %d%s" % [base - 2, MoveStatVisuals.DOWN_ARROW],
			"the chip reports the EFFECTIVE movement, marked as cut")


func test_a_modified_chip_is_tinted_with_the_shared_delta_colour() -> void:
	# Same vocabulary as the move buttons and the forecast: green up, red down. A panel
	# with its own colours is a panel that disagrees with the rest of the HUD.
	var panel: Control = await _make_card()
	var unit := _make_unit()
	unit.add_stat_modifier("defense", 4, -1)
	unit.add_stat_modifier("speed", -3, -1)

	panel._on_unit_selected(unit, Vector3.ZERO)
	await get_tree().process_frame

	var def_value := panel._stat_row.get_node("StatChipDEF/Value") as Label
	var spd_value := panel._stat_row.get_node("StatChipSPD/Value") as Label
	assert_eq(def_value.get_theme_color("font_color"), MoveStatVisuals.BUFF_COLOR,
			"a raised stat is drawn in the shared buff green")
	assert_eq(spd_value.get_theme_color("font_color"), MoveStatVisuals.NERF_COLOR,
			"a cut stat is drawn in the shared nerf red")


# --- The status strip ----------------------------------------------------------

func test_a_unit_with_no_statuses_says_so_rather_than_leaving_a_gap() -> void:
	var panel: Control = await _make_card()
	panel._on_unit_selected(_make_unit(), Vector3.ZERO)
	await get_tree().process_frame

	assert_not_null(panel._status_flow.get_node_or_null("NoStatuses"),
			"an empty strip carries a muted 'No active effects' line, never blank space")


func test_each_active_status_gets_its_own_compact_chip() -> void:
	var panel: Control = await _make_card()
	var unit := _make_unit()
	var controller = unit.get_status_controller()
	controller.add_status(_condition(&"poisoned", "Poisoned", 2))
	controller.add_status(_condition(&"hastened", "Hastened", 3))

	panel._on_unit_selected(unit, Vector3.ZERO)
	await get_tree().process_frame

	var texts: Array = _status_chip_texts(panel)
	assert_eq(texts.size(), 2, "two live conditions, two chips")
	assert_true(texts[0].contains("Poisoned"), "the first chip names the poison")
	assert_true(texts[0].ends_with("2t"), "and compacts its duration to fit the card")


func test_a_stacked_status_is_one_chip_carrying_its_severity() -> void:
	# Three live Poisoned instances are ONE status at severity 3 -- the same grouping the
	# world-space pips and the hover card use. Ungrouped they would eat the whole strip.
	var panel: Control = await _make_card()
	var unit := _make_unit()
	var controller = unit.get_status_controller()
	for i in range(3):
		var poison := _condition(&"poisoned", "Poisoned", 2)
		poison.stacking = StatusCondition.Stacking.STACK
		controller.add_status(poison)

	panel._on_unit_selected(unit, Vector3.ZERO)
	await get_tree().process_frame

	var texts: Array = _status_chip_texts(panel)
	assert_eq(texts.size(), 1, "three instances of one status are one chip")
	assert_true(texts[0].contains("x3"), "carrying the severity: %s" % texts[0])


func test_more_statuses_than_fit_are_counted_not_dropped() -> void:
	var panel: Control = await _make_card()
	var unit := _make_unit()
	var controller = unit.get_status_controller()
	for spec in [[&"poisoned", "Poisoned"], [&"burn", "Burn"], [&"ensnared", "Ensnared"],
			[&"hastened", "Hastened"], [&"fortified", "Fortified"]]:
		controller.add_status(_condition(spec[0], String(spec[1]), 2))

	panel._on_unit_selected(unit, Vector3.ZERO)
	await get_tree().process_frame

	var texts: Array = _status_chip_texts(panel)
	var shown: int = StatusVisuals.shown_count(5, UnitInfoPanel.MAX_STATUS_CHIPS)
	var hidden: int = StatusVisuals.hidden_count(5, UnitInfoPanel.MAX_STATUS_CHIPS)
	assert_eq(texts.size(), shown + 1, "the strip fills its slots and spends the last on overflow")
	assert_eq(texts[texts.size() - 1], StatusVisuals.overflow_label(hidden),
			"the overflow marker COUNTS what did not fit rather than hiding it")


func test_the_strips_height_never_changes_with_its_contents() -> void:
	# A card that grows when a status lands moves the battle log above it, mid-turn. The
	# strip is a fixed-height clipping frame precisely so that cannot happen.
	var panel: Control = await _make_card()
	var unit := _make_unit()
	panel._on_unit_selected(unit, Vector3.ZERO)
	await get_tree().process_frame
	var empty_h: float = panel._status_strip.custom_minimum_size.y

	var controller = unit.get_status_controller()
	for spec in [[&"poisoned", "Poisoned"], [&"burn", "Burn"], [&"ensnared", "Ensnared"],
			[&"hastened", "Hastened"], [&"fortified", "Fortified"]]:
		controller.add_status(_condition(spec[0], String(spec[1]), 2))
	panel._update_unit_info(unit)
	await get_tree().process_frame

	assert_eq(panel._status_strip.custom_minimum_size.y, empty_h,
			"a full strip claims exactly what an empty one claims")
	assert_eq(empty_h, UnitInfoPanel.STATUS_STRIP_HEIGHT, "namely two chip rows")


# --- The compact wording (pure statics) -----------------------------------------

func test_the_compact_turn_count_is_the_same_number_in_less_space() -> void:
	assert_eq(UnitInfoPanel.compact_turns(2), "2t", "two turns left")
	assert_eq(UnitInfoPanel.compact_turns(1), "1t", "one turn left")
	assert_eq(UnitInfoPanel.compact_turns(0), "0t", "about to expire, not 'permanent'")
	assert_eq(UnitInfoPanel.compact_turns(-1), "∞",
			"the permanent sentinel reads as forever, never as a negative count")


func test_a_chip_label_keeps_the_shared_status_grammar() -> void:
	var poison := _condition(&"poisoned", "Poisoned", 2)
	poison.turns_left = 2
	var text: String = UnitInfoPanel.compact_status_text(poison, 3)
	assert_eq(text, "%s Poisoned x3 · 2t" % StatusVisuals.glyph_for(poison),
			"glyph, name, stack suffix, separator, duration -- the same grammar as everywhere else")


# --- What the card must NOT carry ------------------------------------------------

func test_the_card_carries_no_ability_or_move_content() -> void:
	var panel: Control = await _make_card()
	var character := _make_character()
	var ability := AbilityResource.new()
	ability.id = &"grass_cutter"
	ability.display_name = "Grass Cutter"
	ability.description = "Cuts grass."
	character.abilities = [ability]

	var unit := Unit.new()
	unit.character_resource = character
	add_child_autofree(unit)

	panel._on_unit_selected(unit, Vector3.ZERO)
	await get_tree().process_frame

	assert_eq(panel.find_children("*Abilit*", "", true, false).size(), 0,
			"no ability node survives on the compact card")
	assert_eq(panel.find_children("*Move*", "", true, false).size(), 0,
			"nor any move node -- both live on the detail page now")
	for node in panel.find_children("*", "Label", true, false):
		assert_false((node as Label).text.contains("Grass Cutter"),
				"and the ability's name appears nowhere on the card")
