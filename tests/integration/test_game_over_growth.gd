extends GutTest

## GROWTH rows on the REAL mounted end screen (EVOLUTION.md task 1.7), mirroring
## test_game_over_drops.gd: the shipped .tscn is mounted, the per-battle latch is SEEDED, and
## _populate_summary() renders -- show_result() is avoided because the real reveal pauses the
## tree. Rows are found by NAME in the tree, so a row built but never parented would fail.

const SCREEN_SCENE := preload("res://game/ui/screens/GameOverScreen.tscn")

var _screen: GameOverScreen = null


func before_each() -> void:
	GrowthTracker.begin_battle_log()
	_screen = SCREEN_SCENE.instantiate() as GameOverScreen
	add_child_autofree(_screen)


func after_each() -> void:
	GrowthTracker.begin_battle_log()
	_screen = null


func _box() -> VBoxContainer:
	return _screen.find_child("GrowthRows", true, false) as VBoxContainer


func _texts(node: Node, out: Array = []) -> Array:
	for c in node.get_children():
		if c is Label:
			out.append((c as Label).text)
		_texts(c, out)
	return out


func test_no_growth_renders_no_block() -> void:
	_screen._populate_summary()
	assert_not_null(_box(), "the growth block is built with the rewards section")
	assert_false(_box().visible, "a battle that awarded no growth shows no heading and no rows")


func test_seeded_growth_renders_one_row_per_member() -> void:
	GrowthTracker.seed_growth_this_battle([
		{ "uid": "tree_grunt", "character_id": "tree_grunt", "name": "Barkling",
			"gained": 1, "total": 3, "goal": 3, "ready": true },
		{ "uid": "petalfang", "character_id": "petalfang", "name": "Petalfang",
			"gained": 1, "total": 1, "goal": 0, "ready": false },
	])
	_screen._populate_summary()
	var box := _box()
	assert_true(box.visible, "growth was earned, so the block shows")
	var texts := _texts(box)
	assert_true(texts.has("GROWTH"), "under a GROWTH heading")
	assert_true(texts.has("Barkling +1 Growth (3/3)"), "Barkling's row reads '+1 Growth (3/3)'")
	assert_true(texts.has("Ready to evolve!"), "and flags that it is ready to evolve")
	assert_false(texts.any(func(t): return "Petalfang" in t),
		"a unit with no evolution ahead gets no row")
	assert_not_null(box.find_child("Growth_tree_grunt", true, false), "the row is parented in the tree")


func test_a_row_below_the_goal_is_not_ready() -> void:
	GrowthTracker.seed_growth_this_battle([
		{ "uid": "tree_grunt", "name": "Barkling", "gained": 1, "total": 1, "goal": 3, "ready": false },
	])
	_screen._populate_summary()
	var texts := _texts(_box())
	assert_true(texts.has("Barkling +1 Growth (1/3)"), "the row counts toward the goal")
	assert_false(texts.has("Ready to evolve!"), "and is not flagged ready")
	var lit: int = 0
	for gem in _box().find_children("Gem*", "GroveGem", true, false):
		if bool(gem.get_meta(&"lit", false)):
			lit += 1
	assert_eq(lit, 1, "one of three gems is lit")
