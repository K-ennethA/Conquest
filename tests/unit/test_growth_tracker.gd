extends GutTest

## [GrowthTracker]'s pure halves (EVOLUTION.md §4.1, task 1.4): the award maths
## [method GrowthTracker.compute_awards] and the gate [method GrowthTracker.gate_reason]. No
## tree, no ledger, no disk -- the live half is tests/integration/test_growth_tracker_live.gd.


static func _rules(per_win: int = 1, per_ko: int = 0, ko_cap: int = 2, on_loss: int = 0) -> EvolutionRules:
	var r := EvolutionRules.new()
	r.growth_per_win = per_win
	r.growth_per_ko = per_ko
	r.growth_ko_cap = ko_cap
	r.growth_on_loss = on_loss
	return r


func test_a_win_rewards_survivors_only() -> void:
	var rows := [
		{ "uid": "tree_grunt", "alive": true, "kos": 0 },
		{ "uid": "vineweave", "alive": false, "kos": 1 },
	]
	var awards := GrowthTracker.compute_awards(rows, true, _rules())
	assert_eq(awards, { "tree_grunt": 1 }, "the survivor earns growth_per_win; the fallen unit earns nothing")


func test_a_loss_awards_participation_growth_only_when_tuned_on() -> void:
	var rows := [{ "uid": "tree_grunt", "alive": true, "kos": 3 }, { "uid": "geode", "alive": false, "kos": 0 }]
	assert_eq(GrowthTracker.compute_awards(rows, false, _rules()), {},
		"the shipped default: a defeat earns nothing")
	assert_eq(GrowthTracker.compute_awards(rows, false, _rules(1, 0, 2, 1)), { "tree_grunt": 1, "geode": 1 },
		"with growth_on_loss 1 every fielded unit, alive or not, earns it")


func test_ko_bonus_is_capped() -> void:
	var rows := [{ "uid": "tree_grunt", "alive": true, "kos": 5 }, { "uid": "petalfang", "alive": true, "kos": 1 }]
	var awards := GrowthTracker.compute_awards(rows, true, _rules(1, 1, 2))
	assert_eq(int(awards["tree_grunt"]), 3, "1 per win + min(5 KOs, cap 2) = 3")
	assert_eq(int(awards["petalfang"]), 2, "1 per win + 1 KO = 2")


func test_kos_do_not_count_in_the_shipped_rules() -> void:
	var rows := [{ "uid": "tree_grunt", "alive": true, "kos": 4 }]
	assert_eq(GrowthTracker.compute_awards(rows, true, EvolutionRules.current()), { "tree_grunt": 1 },
		"growth_per_ko ships at 0: a win is worth exactly one Growth")


func test_one_member_is_awarded_once_per_battle() -> void:
	var rows := [{ "uid": "tree_grunt", "alive": true, "kos": 0 }, { "uid": "tree_grunt", "alive": true, "kos": 0 }]
	assert_eq(GrowthTracker.compute_awards(rows, true, _rules()), { "tree_grunt": 1 },
		"two units of the same member (e.g. Barkling and Oakheart both fielded) earn one award")


func test_gates() -> void:
	var rules := EvolutionRules.current()
	assert_eq(GrowthTracker.gate_reason({ "mode": "skirmish" }, rules), "", "a plain skirmish earns growth")
	assert_eq(GrowthTracker.gate_reason({ "mode": "campaign" }, rules), "", "a campaign battle earns growth")
	assert_eq(GrowthTracker.gate_reason({ "mode": "challenge" }, rules), "", "a challenge earns growth")
	assert_eq(GrowthTracker.gate_reason({ "mode": "skirmish", "replay": true }, rules), "replay",
		"watching a replay never earns growth")
	assert_eq(GrowthTracker.gate_reason({ "mode": "skirmish", "networked": true }, rules), "networked",
		"a networked versus match never earns growth")
	assert_eq(GrowthTracker.gate_reason({ "mode": "arena", "arena": true }, rules), "arena",
		"an arena run never earns growth")
	assert_eq(GrowthTracker.gate_reason({ "mode": "versus" }, rules), "mode",
		"hotseat versus is not a growth mode")
	assert_eq(GrowthTracker.gate_reason({ "mode": "story" }, rules), "",
		"story battles earn growth (growth_modes lists \"story\" -- data, not code)")
	assert_eq(GrowthTracker.gate_reason({ "mode": "duel" }, rules), "mode",
		"standalone duels do not earn growth unless growth_modes lists \"duel\"")


func test_result_rows_skip_forms_with_nothing_to_grow_into() -> void:
	var box := VBoxContainer.new()
	autofree(box)
	var added := GrowthGems.fill_result_rows(box, [
		{ "uid": "tree_grunt", "name": "Barkling", "gained": 1, "total": 3, "goal": 3, "ready": true },
		{ "uid": "vineweave", "name": "Vineweave", "gained": 1, "total": 4, "goal": 0, "ready": false },
	], 15)
	assert_eq(added, 1, "only the member with an evolution ahead gets a row")
	assert_eq(GrowthGems.result_line({ "name": "Barkling", "gained": 1, "total": 3, "goal": 3 }),
		"Barkling +1 Growth (3/3)", "the row reads like the design doc")
	assert_eq(GrowthGems.fill_result_rows(box, [], 15), 0, "an empty latch adds nothing")
	assert_false(box.visible, "and hides the block")
