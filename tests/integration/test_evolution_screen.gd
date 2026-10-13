extends GutTest

## The EVOLUTION MOMENT on real Controls (EVOLUTION.md task 1.6) and its Character Select entry
## point (task 1.5): open -> Evolve commits through RosterLedger.evolve and finishes with
## (true, edge); Not now leaves the ledger untouched; the animations-off path reaches the reveal
## at once; and the EVOLVE button in Character Select appears at the goal, opens the screen, and
## the roster is rebuilt with the new form pickable.
##
## The edge is the test-only Barkling -> Mycothrall one (Growth 3 + 2 wins,
## tests/helpers/evolution_fixture.gd), served beside the shipped content and dropped after each
## test. Ledger + inventory go to temp files; GameSettings fields are snapshot by the guard
## (tests/README.md rules 3 and 4). Nothing waits on wall-clock time: the animated path is
## skipped with dismiss(), which is also what Esc does mid-animation.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const CHARACTER_SELECT := preload("res://menus/CharacterSelect.tscn")
const LEDGER_PATH := "user://test_evo_screen_ledger.json"
const ITEMS_PATH := "user://test_evo_screen_items.json"
const EvoFixture := preload("res://tests/helpers/evolution_fixture.gd")

## Untyped on purpose (tests/README.md rule 3).
var _guard
var _edge: EvolutionResource = null
var _finished: Array = []


func before_all() -> void:
	RosterLedger.set_save_path(LEDGER_PATH)
	ItemInventory.set_save_path(ITEMS_PATH)
	EvolutionLibrary.rescan()


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	_guard.watch_setting("selected_squad")
	RosterLedger.reset()
	ItemInventory.reset()
	_edge = EvoFixture.install()
	_finished.clear()


func after_each() -> void:
	_guard.restore()
	RosterLedger.reset()
	ItemInventory.reset()
	EvoFixture.uninstall()


func after_all() -> void:
	for path in [LEDGER_PATH, ITEMS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	RosterLedger.set_save_path(RosterLedger.DEFAULT_SAVE_PATH)
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)


func _ready_to_evolve() -> void:
	RosterLedger.add_growth("tree_grunt", _edge.growth_goal())
	RosterLedger.add_feats("tree_grunt", {"wins": 2})   # Growth 3 + 2 wins (EVOLUTION.md §3.2a)


func _on_finished(evolved: bool, edge) -> void:
	_finished.append([evolved, edge])


func _open() -> EvolutionScreen:
	var host := Control.new()
	add_child_autofree(host)
	var screen := EvolutionScreen.open(host, "tree_grunt", RosterLedger.available_evolutions("tree_grunt"))
	screen.finished.connect(_on_finished)
	return screen


func _texts(node: Node, out: Array = []) -> Array:
	for c in node.get_children():
		if c is Label:
			out.append((c as Label).text)
		_texts(c, out)
	return out


# --- EvolutionScreen ---------------------------------------------------------------

func test_the_prompt_names_the_evolving_unit_and_hides_the_new_form() -> void:
	_ready_to_evolve()
	var screen := _open()
	await get_tree().process_frame
	assert_eq(screen.phase, EvolutionScreen.Phase.PROMPT, "the screen opens on the prompt")
	var texts := _texts(screen)
	assert_true(texts.has("Barkling is evolving..."), "the ribbon reads 'Barkling is evolving...'")
	assert_false(texts.has(EvoFixture.TO_NAME), "the new form stays a mystery until the reveal")
	assert_true(screen.evolve_button.visible and screen.not_now_button.visible, "Evolve and Not now are offered")


func test_confirm_evolves_through_the_ledger_and_finishes_true() -> void:
	_ready_to_evolve()
	var screen := _open()
	await get_tree().process_frame
	var result := screen.confirm()
	assert_true(bool(result["success"]), "Evolve commits through RosterLedger.evolve")
	assert_eq(RosterLedger.form_of("tree_grunt"), EvoFixture.TO_ID, "the ledger now says Mycothrall")
	assert_true(RosterLedger.is_form_unlocked(String(EvoFixture.TO_ID)), "and Mycothrall is unlocked")
	assert_eq(screen.phase, EvolutionScreen.Phase.REVEAL, "animations off: the reveal shows at once")
	var texts := _texts(screen)
	assert_true(texts.has("Barkling evolved into Mycothrall!"), "the ribbon announces the result")
	# What the reveal must show, read off the two forms (the pure helpers are pinned below).
	var bark := CharacterLibrary.get_character(EvoFixture.FROM_ID)
	var to := CharacterLibrary.get_character(EvoFixture.TO_ID)
	var move_name: String = EvolutionScreen.new_moves(bark, to)[0].display_name
	var ability_name: String = EvolutionScreen.new_abilities(bark, to)[0].display_name
	var hp_delta: int = int(EvolutionScreen.stat_diff(bark, to)[0]["delta"])
	var hp_text: String = ("+%d" % hp_delta) if hp_delta > 0 else str(hp_delta)
	assert_true(texts.any(func(t): return move_name in t), "the new move (%s) is shown" % move_name)
	assert_true(texts.any(func(t): return ability_name in t), "and the new ability (%s)" % ability_name)
	assert_ne(hp_delta, 0, "the forms' HP differ, so the diff has a number to show")
	assert_true(texts.has(hp_text), "the stat diff shows the HP change as %s" % hp_text)
	assert_eq(_finished.size(), 0, "nothing has finished while the reveal is up")
	screen.dismiss()
	assert_eq(_finished.size(), 1, "Continue finishes exactly once")
	assert_eq(_finished[0], [true, _edge], "with (true, the edge taken)")
	screen.dismiss()
	assert_eq(_finished.size(), 1, "a second dismiss never re-emits")
	await get_tree().process_frame  # let the swapped-out preview model free (no orphans)


func test_not_now_leaves_the_ledger_untouched() -> void:
	_ready_to_evolve()
	var screen := _open()
	await get_tree().process_frame
	screen.decline()
	assert_eq(_finished, [[false, null]], "Not now finishes with (false, null)")
	assert_eq(RosterLedger.form_of("tree_grunt"), &"tree_grunt", "Barkling is still Barkling")
	assert_false(RosterLedger.is_form_unlocked(String(EvoFixture.TO_ID)), "nothing was unlocked")
	assert_eq(RosterLedger.available_evolutions("tree_grunt").size(), 1, "the offer stays open")


func test_escape_is_not_now_on_the_prompt() -> void:
	_ready_to_evolve()
	var screen := _open()
	await get_tree().process_frame
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	screen._unhandled_input(esc)
	assert_eq(_finished, [[false, null]], "Esc / pad B on the prompt is Not now")


func test_the_animated_path_can_be_skipped_to_the_reveal() -> void:
	_guard.set_setting("animations_enabled", true)
	_ready_to_evolve()
	var screen := _open()
	await get_tree().process_frame
	screen.confirm()
	assert_eq(screen.phase, EvolutionScreen.Phase.ANIMATING, "animations on: the change plays first")
	assert_eq(RosterLedger.form_of("tree_grunt"), EvoFixture.TO_ID, "but the ledger is already committed")
	screen.dismiss()
	assert_eq(screen.phase, EvolutionScreen.Phase.REVEAL, "skipping lands on the reveal")
	screen.dismiss()
	assert_eq(_finished, [[true, _edge]], "and Continue finishes true")
	await get_tree().process_frame


func test_nothing_to_offer_finishes_false_instead_of_hanging() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var screen := EvolutionScreen.open(host, "tree_grunt", [])
	screen.finished.connect(_on_finished)
	await get_tree().process_frame
	assert_eq(_finished, [[false, null]], "an empty offer reports 'not evolved' on its own")


## An in-code form for the pure diff helpers (independent of the roster's tuning).
static func _form(id: String, hp: int, moves: Array, abilities: Array) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = StringName(id)
	c.display_name = id.capitalize()
	c.base_health = hp
	var ms: Array[MoveResource] = []
	for mid in moves:
		var m := MoveResource.new()
		m.move_id = StringName(mid)
		m.display_name = String(mid).capitalize()
		ms.append(m)
	c.moveset = ms
	var abs_: Array[AbilityResource] = []
	for aid in abilities:
		var a := AbilityResource.new()
		a.id = StringName(aid)
		abs_.append(a)
	c.abilities = abs_
	return c


func test_the_diff_helpers_read_the_forms() -> void:
	var sapling := _form("sapling", 55, ["tree_bash", "rooted"], ["natures_blessing"])
	var tree := _form("tree", 96, ["rooted", "bough_sweep", "timberfall"], ["natures_blessing", "thornskin"])
	var hp: Dictionary = EvolutionScreen.stat_diff(sapling, tree)[0]
	assert_eq([hp["key"], hp["from"], hp["to"], hp["delta"]], ["health", 55, 96, 41], "HP 55 -> 96")
	var new_ids: Array = EvolutionScreen.new_moves(sapling, tree).map(func(m): return String(m.move_id))
	assert_eq(new_ids, ["bough_sweep", "timberfall"], "the moves it lacked are new, in slot order")
	var lost_ids: Array = EvolutionScreen.lost_moves(sapling, tree).map(func(m): return String(m.move_id))
	assert_eq(lost_ids, ["tree_bash"], "the move the new form lacks is replaced")
	var abil: Array = EvolutionScreen.new_abilities(sapling, tree).map(func(a): return String(a.id))
	assert_eq(abil, ["thornskin"], "only the ability it did not have is new")
	assert_eq(EvolutionScreen.stat_diff(null, tree), [], "a missing form diffs to nothing")


# --- Character Select entry point ---------------------------------------------------

## Untyped return: the tests call the screen script's own members.
func _character_select():
	var cs = CHARACTER_SELECT.instantiate()
	add_child_autofree(cs)
	return cs


func test_character_select_hides_the_evolved_form_until_it_is_unlocked() -> void:
	var cs = _character_select()
	await get_tree().process_frame
	assert_null(cs.find_child("Unit_%s" % EvoFixture.TO_ID, true, false), "a locked evolved form is not on the roster")
	assert_not_null(cs.find_child("Unit_tree_grunt", true, false), "Barkling is")


func test_evolve_button_appears_at_the_goal_and_evolving_adds_the_new_form() -> void:
	ItemInventory.grant("ironbark_sigil")
	ItemInventory.equip("tree_grunt", "ironbark_sigil")
	_ready_to_evolve()
	var cs = _character_select()
	await get_tree().process_frame
	cs._show_detail("tree_grunt")
	var block := cs.find_child("EvolutionBlock", true, false) as EvolutionDetailBlock
	assert_not_null(block, "the detail pane carries the Growth block")
	assert_true(block.visible, "shown for Barkling, who is in a line")
	assert_true(block.evolve_button.visible, "EVOLVE is offered at the goal")
	var pips := cs.find_child("Unit_tree_grunt", true, false).find_child("GrowthPips", true, false)
	assert_not_null(pips, "Barkling's roster card carries growth pips")

	block.evolve_button.pressed.emit()
	await get_tree().process_frame
	var evo: EvolutionScreen = null
	for c in cs.get_children():
		if c is EvolutionScreen:
			evo = c
	assert_not_null(evo, "EVOLVE opens the Evolution screen over Character Select")
	evo.confirm()
	evo.dismiss()
	await get_tree().process_frame
	assert_not_null(cs.find_child("Unit_%s" % EvoFixture.TO_ID, true, false), "Mycothrall is now on the roster")
	assert_not_null(cs.find_child("Unit_tree_grunt", true, false), "and Barkling stays pickable")
	assert_eq(ItemInventory.equipped_item(String(EvoFixture.TO_ID)), "ironbark_sigil", "the Ironbark Sigil moved to Mycothrall")


func test_evolve_button_is_hidden_below_the_goal() -> void:
	RosterLedger.add_growth("tree_grunt", _edge.growth_goal() - 1)
	var cs = _character_select()
	await get_tree().process_frame
	cs._show_detail("tree_grunt")
	var block := cs.find_child("EvolutionBlock", true, false) as EvolutionDetailBlock
	assert_false(block.evolve_button.visible, "no EVOLVE below the goal")
	var lit: int = 0
	for gem in block.find_children("Gem*", "GroveGem", true, false):
		if bool(gem.get_meta(&"lit", false)):
			lit += 1
	assert_eq(lit, _edge.growth_goal() - 1, "one lit gem per Growth earned")
	await get_tree().process_frame
