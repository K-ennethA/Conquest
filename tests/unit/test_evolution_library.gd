extends GutTest

## EVOLUTION data layer (docs/design/EVOLUTION.md §3.2-3.4, task 1.1/1.2): the graph queries
## and the content validator, proven over FIXTURE edges and characters built in code (never
## broken files on disk), plus the gates over the shipped content (Barkling -> Oakheart).


# --- Fixtures -----------------------------------------------------------------

## A roster character with a chosen power budget (HP carries the difference).
static func _char(id: String, budget: int = 100, is_boss: bool = false, footprint: Vector2i = Vector2i.ONE) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = StringName(id)
	c.display_name = id.capitalize()
	c.base_attack = 0
	c.base_defense = 0
	c.base_magic = 0
	c.base_magic_defense = 0
	c.base_speed = 0
	c.base_movement = 0
	c.base_health = budget
	c.is_boss = is_boss
	c.footprint = footprint
	return c


static func _edge(from: String, to: String, growth: int = 3, id: String = "") -> EvolutionResource:
	var e := EvolutionResource.new()
	e.id = StringName(id if id != "" else "%s__%s" % [from, to])
	e.from_id = StringName(from)
	e.to_id = StringName(to)
	var t := GrowthTrigger.new()
	t.growth_required = growth
	e.triggers = [t]
	return e


## A lookup Callable over a Dictionary of fixture characters.
static func _lookup(chars: Array) -> Callable:
	var by_id: Dictionary = {}
	for c in chars:
		by_id[c.character_id] = c
	return func(id) -> CharacterResource: return by_id.get(StringName(id), null)


# --- Graph queries --------------------------------------------------------------

func test_line_walks_resolve_root_stage_and_line() -> void:
	var g := EvolutionGraph.new([_edge("seed", "sprout"), _edge("sprout", "tree", 6)])
	assert_eq(g.line_root(&"tree"), &"seed", "the root of a stage-3 form is the base form")
	assert_eq(g.line_root(&"seed"), &"seed", "a base form is its own root")
	assert_eq(g.stage_of(&"seed"), 1, "the base form is stage 1")
	assert_eq(g.stage_of(&"tree"), 3, "two edges up the line is stage 3")
	assert_eq(g.parent_of(&"sprout"), &"seed", "a form evolves from exactly its parent")
	assert_eq(g.line_of(&"sprout"), [&"seed", &"sprout", &"tree"] as Array[StringName],
		"line_of lists the whole line root-first from any member")
	assert_true(g.is_evolved_form(&"tree"), "a reached form is an evolved form")
	assert_false(g.is_evolved_form(&"seed"), "the base form is not")
	assert_false(g.in_any_line(&"stranger"), "an id in no edge is in no line")
	assert_eq(g.line_root(&"stranger"), &"stranger", "and is its own root, stage 1")


func test_branching_edges_share_a_parent() -> void:
	var g := EvolutionGraph.new([_edge("seed", "oak"), _edge("seed", "ember", 5)])
	var tos: Array = g.edges_from(&"seed").map(func(e): return String(e.to_id))
	tos.sort()
	assert_eq(tos, ["ember", "oak"], "a branching form lists every edge out of it")
	assert_not_null(g.edge_between(&"seed", &"ember"), "edge_between finds a specific branch")
	assert_null(g.edge_between(&"oak", &"seed"), "and never an edge that goes backwards")
	assert_eq(g.line_of(&"oak").size(), 3, "a branching line holds the root and both branches")


func test_edge_availability_is_any_trigger() -> void:
	var e := _edge("seed", "oak", 3)
	assert_false(e.is_available({"growth": 2}), "growth 2 does not meet a Growth 3 trigger")
	assert_true(e.is_available({"growth": 3}), "growth 3 meets it")
	assert_eq(e.growth_goal(), 3, "the edge reports its growth goal for the pips")
	assert_eq(e.describe_triggers(), "Growth 3", "and describes its trigger for the UI")
	var none := EvolutionResource.new()
	assert_false(none.is_available({"growth": 99}), "an edge with no triggers is never available out of battle")


# --- Validation -------------------------------------------------------------------

func test_a_clean_fixture_validates_empty() -> void:
	var chars := [_char("seed", 100), _char("sprout", 150)]
	var g := EvolutionGraph.new([_edge("seed", "sprout")])
	assert_eq(g.validate(_lookup(chars), 1.75), [] as Array[String], "a sound line has no problems")


func test_validate_catches_a_missing_id() -> void:
	var g := EvolutionGraph.new([_edge("seed", "ghost")])
	var problems := g.validate(_lookup([_char("seed")]), 1.75)
	assert_eq(problems.size(), 1, "one problem: the to-form is not a roster character")
	assert_string_contains(problems[0], "ghost", "and it names the missing id")


func test_validate_catches_a_second_parent() -> void:
	var chars := [_char("a", 100), _char("b", 100), _char("c", 150)]
	var g := EvolutionGraph.new([_edge("a", "c"), _edge("b", "c")])
	var problems := g.validate(_lookup(chars), 1.75)
	assert_true(problems.any(func(p): return "second parent" in p), "a form reached from two parents is refused")


func test_validate_catches_a_cycle() -> void:
	var chars := [_char("a", 100), _char("b", 100)]
	var g := EvolutionGraph.new([_edge("a", "b"), _edge("b", "a")])
	var problems := g.validate(_lookup(chars), 1.75)
	assert_true(problems.any(func(p): return "cycle" in p), "a -> b -> a is a cycle")


func test_validate_catches_a_budget_out_of_bounds() -> void:
	var chars := [_char("weak", 100), _char("huge", 200), _char("weaker", 90)]
	var g := EvolutionGraph.new([_edge("weak", "huge", 3, "up"), _edge("huge", "weaker", 3, "down")])
	var problems := g.validate(_lookup(chars), 1.75)
	assert_true(problems.any(func(p): return "ceiling" in p), "x2.0 growth is over a x1.75 ceiling")
	assert_true(problems.any(func(p): return "weaker" in p and "budget" in p), "an evolution may not lose power")


func test_validate_refuses_boss_forms_except_in_battle_phase_changes() -> void:
	var chars := [_char("minion", 100), _char("king", 150, true)]
	var player_edge := _edge("minion", "king")
	assert_true(EvolutionGraph.new([player_edge]).validate(_lookup(chars), 1.75).any(
		func(p): return "boss" in p), "a player may not evolve into a boss out of battle")
	var phase := _edge("minion", "king")
	phase.allowed_in_battle = true
	assert_eq(EvolutionGraph.new([phase]).validate(_lookup(chars), 1.75), [] as Array[String],
		"an in-battle edge INTO a boss form (a phase change) is allowed")


func test_validate_refuses_in_battle_footprint_changes() -> void:
	var chars := [_char("small", 100), _char("large", 150, false, Vector2i(2, 2))]
	var e := _edge("small", "large")
	e.allowed_in_battle = true
	assert_true(EvolutionGraph.new([e]).validate(_lookup(chars), 1.75).any(
		func(p): return "footprint" in p), "a mid-battle evolution may not change the footprint")


# --- Shipped content -----------------------------------------------------------------

func test_shipped_content_validates_clean() -> void:
	EvolutionLibrary.rescan()
	assert_eq(EvolutionLibrary.validate(), [] as Array[String], "every shipped evolution edge is sound")


func test_barkling_evolves_into_oakheart() -> void:
	EvolutionLibrary.rescan()
	var edge := EvolutionLibrary.get_edge(&"tree_grunt__oakheart")
	assert_not_null(edge, "the slice edge ships")
	assert_eq(edge.from_id, &"tree_grunt", "from Barkling")
	assert_eq(edge.to_id, &"oakheart", "into Oakheart")
	assert_eq(EvolutionLibrary.line_root(&"oakheart"), &"tree_grunt", "Oakheart's line root is Barkling")
	assert_eq(EvolutionLibrary.stage_of(&"oakheart"), 2, "Oakheart is stage 2")
	assert_eq(EvolutionLibrary.stage_of(&"tree_grunt"), 1, "Barkling is stage 1")
	assert_gt(edge.growth_goal(), 0, "the slice edge is earned through Growth")


func test_oakheart_is_a_valid_one_word_unit_within_the_budget_ceiling() -> void:
	var oak := CharacterLibrary.get_character(&"oakheart")
	var bark := CharacterLibrary.get_character(&"tree_grunt")
	assert_not_null(oak, "oakheart.tres is in the roster")
	assert_true(bool(oak.validate()["valid"]), "Oakheart passes the character validator: %s" % str(oak.validate()["issues"]))
	assert_false(" " in oak.display_name, "a non-boss unit name is one word (CONQUEST.md)")
	assert_false(oak.is_boss, "Oakheart is a player unit, not a boss")
	assert_eq(oak.get_footprint(), Vector2i.ONE, "Oakheart is 1x1")
	assert_eq(oak.element, bark.element, "Oakheart keeps the nature element")
	var ratio := float(oak.power_budget()) / float(bark.power_budget())
	assert_true(ratio >= 1.0 and ratio <= EvolutionRules.current().max_budget_growth,
		"the budget ratio %.2f is within [1, max_budget_growth]" % ratio)
	assert_eq(oak.move_count(), 4, "evolving fills the empty ultimate slot")
	assert_true(MoveResource.is_ultimate_move(oak.get_move(3), 3), "slot 3 (Timberfall) is the ultimate")


func test_rules_resource_ships_the_documented_defaults() -> void:
	var rules := EvolutionRules.current()
	assert_eq(rules.growth_per_win, 1, "one Growth per surviving win")
	assert_true(rules.earns_growth_in("skirmish"), "skirmish earns growth")
	assert_false(rules.earns_growth_in("arena"), "arena does not")
	assert_false(rules.earns_growth_in("versus"), "versus does not")
	assert_true(rules.hide_locked_forms, "locked forms are hidden by default")
