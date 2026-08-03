extends GutTest

## The full-screen UNIT DETAIL page ([UnitDetailPage]) -- the half of the old unit card
## that moved OFF the battle HUD.
##
## What this suite exists to pin:
##   * everything the compact card dropped is actually HERE (full stat table with
##     base → effective deltas, every move, every ability, every active status);
##   * live battle state reaches the cards -- a move on cooldown says so, which is the
##     whole reason this page is not just the compendium's unit page;
##   * it works identically for an inspected ENEMY, because it only ever READS;
##   * ESC closes it and hands the battle back untouched -- and it NEVER pauses the tree,
##     because a networked match keeps running while one player reads a stat sheet.
##
## No compendium data source is stubbed: the page is built from a crafted
## [CharacterResource] handed straight to a real [Unit], which is exactly the shape
## [UnitPageContent] reads. That keeps the suite off CharacterLibrary's disk scan.

var _page: UnitDetailPage = null


func before_each() -> void:
	_page = UnitDetailPage.new()
	add_child_autofree(_page)


func after_each() -> void:
	# A test that fails mid-way must not leave the tree paused for the next suite. The
	# page never pauses it, so this only ever restores a pause some OTHER code set.
	get_tree().paused = false
	# Re-populating the page detaches the previous unit's cards and queue_free()s them
	# (see UnitPageContent.clear_container). queue_free is DEFERRED, and GUT counts
	# orphans before the frame ends -- so give the detached cards the frame they need,
	# or every re-populate in this suite is reported as a leak. Target: zero orphans.
	await get_tree().process_frame
	await get_tree().process_frame


# --- Fixtures ------------------------------------------------------------------

func _move(id: StringName, name_text: String, cooldown: int) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = id
	m.display_name = name_text
	m.description = "Does a thing."
	m.cooldown = cooldown
	return m


func _ability(id: StringName, name_text: String, description: String) -> AbilityResource:
	var a := AbilityResource.new()
	a.id = id
	a.display_name = name_text
	a.description = description
	a.trigger = AbilityTrigger.Trigger.PASSIVE
	return a


func _character() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"vineweave"
	c.display_name = "Torvald"
	c.description = "A stout root-knight."
	c.base_health = 40
	c.base_attack = 20
	c.base_defense = 15
	c.base_speed = 12
	c.base_movement = 3
	c.moveset = [_move(&"root_slam", "Root Slam", 3), _move(&"guard", "Guard", 0)]
	c.abilities = [_ability(&"grass_cutter", "Grass Cutter", "Ignores rough terrain.")]
	return c


func _unit() -> Unit:
	var u := Unit.new()
	u.character_resource = _character()
	add_child_autofree(u)  # _ready builds MovesetController + StatusController
	return u


## Every Label's text on the page, flattened -- the page is a document, so "does it say
## X" is the honest question to ask of it.
func _page_text() -> String:
	var parts: PackedStringArray = []
	for node in _page.find_children("*", "Label", true, false):
		parts.append((node as Label).text)
	return "\n".join(parts)


func _open(unit: Unit) -> void:
	_page.open(unit)
	await get_tree().process_frame


# --- What the page carries -------------------------------------------------------

func test_the_page_carries_everything_the_compact_card_dropped() -> void:
	await _open(_unit())
	var text: String = _page_text()

	assert_true(_page.is_open(), "the page is on screen")
	assert_true(text.contains("Torvald"), "it names the unit")
	assert_true(text.contains("STATISTICS"), "it has the full stat table")
	assert_true(text.contains("MOVES"), "and a moves section")
	assert_true(text.contains("Root Slam"), "listing every authored move")
	assert_true(text.contains("Guard"), "including the second one")
	assert_true(text.contains("ABILITIES"), "and an abilities section")
	assert_true(text.contains("Grass Cutter"), "naming the ability")
	assert_true(text.contains("Ignores rough terrain."),
			"with its FULL description -- the thing that was cut off on the old card")


func test_the_stat_table_reports_base_and_effective_when_a_stat_is_modified() -> void:
	var unit := _unit()
	var base: int = unit.get_base_stat("attack")
	unit.add_stat_modifier("attack", 7, -1)

	await _open(unit)
	var text: String = _page_text()

	assert_true(text.contains("%d → %d" % [base, base + 7]),
			"a buffed stat shows what it WAS and what it IS, not just the new number")
	assert_true(text.contains("%d / %d" % [unit.current_health, unit.max_health]),
			"and health is the live current/max, not the authored maximum")


func test_a_move_on_cooldown_reports_its_remaining_turns() -> void:
	# The live half of the page. The compendium's identical card says "Cooldown 3 turns"
	# (what it costs); only the in-battle page can say "2 turns left" (what you have).
	var unit := _unit()
	var controller = unit.get_moveset_controller()
	controller.on_used(unit.get_move(0))
	controller.tick_cooldowns()
	assert_eq(controller.remaining(unit.get_move(0)), 2, "the move has two turns to go")

	await _open(unit)
	var text: String = _page_text()

	assert_true(text.contains("Recharging: 2 turns left (of 3)"),
			"the page reports the LIVE recharge, not just the authored cooldown")


func test_a_ready_move_carries_no_live_line_at_all() -> void:
	await _open(_unit())
	assert_false(_page_text().contains("Recharging"),
			"a ready move reads exactly as the compendium's static card")


func test_active_statuses_are_listed_with_what_they_do_and_how_long() -> void:
	var unit := _unit()
	var poison := StatusCondition.new()
	poison.id = &"poisoned"
	poison.display_name = "Poisoned"
	poison.duration_turns = 4
	poison.rule_flags = {"immobilized": true}
	unit.get_status_controller().add_status(poison)

	await _open(unit)
	var text: String = _page_text()

	assert_true(text.contains("ACTIVE STATUSES"), "the page has a statuses section")
	assert_true(text.contains("Poisoned"), "naming the condition")
	assert_true(text.contains("4 turns"), "with its remaining turns spelled out in full")
	assert_true(text.contains("Cannot move"),
			"and a plain-English description of what it is doing to the unit")


func test_a_unit_with_no_statuses_says_so() -> void:
	await _open(_unit())
	assert_true(_page_text().contains("No active statuses."),
			"an empty section states the fact rather than leaving a gap")


# --- Enemies read exactly the same ------------------------------------------------

func test_an_inspected_enemy_renders_the_same_page() -> void:
	# Selection is inspection: an enemy can be clicked to read it, and this page is what
	# the player reads it WITH. It only ever reads, so there is nothing to gate.
	var enemy := _unit()
	# Player is a Resource, so it is reference-counted -- nothing to free, nothing to leak.
	var player := Player.new(1, "Wildwood")
	player.is_ai = true
	enemy.owner_player = player

	await _open(enemy)
	var text: String = _page_text()

	assert_true(_page.is_open(), "an enemy opens the page exactly like an own unit")
	assert_true(text.contains("Root Slam"), "with its full moveset visible")
	assert_true(text.contains("Grass Cutter"), "and its abilities")
	assert_true(text.contains("AI"), "labelled as an AI-owned unit so the player knows whose it is")


func test_opening_the_page_touches_nothing_on_the_unit() -> void:
	var unit := _unit()
	var hp_before: int = unit.current_health
	var acted_before: bool = unit.has_acted_this_turn
	var moved_before: bool = unit.has_moved_this_turn

	await _open(unit)
	_page.close()
	await get_tree().process_frame

	assert_eq(unit.current_health, hp_before, "no HP moved")
	assert_false(unit.has_acted_this_turn != acted_before, "the unit did not act")
	assert_false(unit.has_moved_this_turn != moved_before, "nor move")
	assert_eq(unit.get_moveset_controller().remaining(unit.get_move(0)), 0,
			"and no cooldown was started by looking at the moveset")


# --- Open / close behaviour --------------------------------------------------------

func test_escape_closes_the_page_and_gives_the_battle_back() -> void:
	var unit := _unit()
	await _open(unit)

	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_page._input(escape)
	await get_tree().process_frame

	assert_false(_page.is_open(), "Escape closes the page")
	assert_null(_page.current_unit(), "and drops its reference to the unit")
	assert_true(is_instance_valid(unit), "which the battle still owns")


func test_the_close_button_does_the_same_thing_as_escape() -> void:
	await _open(_unit())
	var button := _page.find_child("CloseButton", true, false) as Button
	assert_not_null(button, "the page has a Close control for players without a keyboard")
	button.pressed.emit()
	await get_tree().process_frame
	assert_false(_page.is_open(), "pressing it closes the page")


func test_the_page_never_pauses_the_tree() -> void:
	# DELIBERATE, and the one place this page differs from the pause menu: a networked
	# match keeps running while a player reads a stat sheet. Freezing the simulation here
	# would desync the other client.
	assert_false(get_tree().paused, "nothing is paused before")
	await _open(_unit())
	assert_false(get_tree().paused, "opening the page leaves the battle running")
	_page.close()
	await get_tree().process_frame
	assert_false(get_tree().paused, "and closing it changes nothing either")


func test_the_page_sits_above_the_hud_and_below_the_pause_menu() -> void:
	assert_true(UnitDetailPage.OVERLAY_LAYER > TurnTransition.OVERLAY_LAYER,
			"the page draws over the turn wipe and every HUD panel")
	assert_true(UnitDetailPage.OVERLAY_LAYER < PauseMenu.OVERLAY_LAYER,
			"but the pause menu still draws over the page")


func test_opening_on_nothing_is_ignored_rather_than_showing_an_empty_page() -> void:
	_page.open(null)
	await get_tree().process_frame
	assert_false(_page.is_open(), "a null subject means there is nothing to show")


func test_open_for_finds_the_battles_existing_page_instead_of_stacking_another() -> void:
	# Both openers -- the card's DETAILS chip and the sidebar's DETAILS button -- go
	# through open_for. Two overlays on top of each other would be one ESC too many.
	var unit := _unit()
	var first := UnitDetailPage.open_for(self, unit)
	assert_eq(first, _page, "it finds the page this battle already mounted")

	var second := UnitDetailPage.open_for(self, unit)
	assert_eq(second, _page, "and keeps finding the same one")
	assert_eq(get_tree().get_nodes_in_group(UnitDetailPage.GROUP).size(), 1,
			"so there is never more than one detail page in the tree")
	_page.close()
