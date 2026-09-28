extends GutTest

## [GrowthTracker] on REAL units (EVOLUTION.md task 1.4): character-backed Units owned by real
## [Player]s fight a tiny battle -- the human squad is Barkling + Vineweave, the enemy one
## Blightcap. Vineweave and the Blightcap fall, the human side wins, and only the SURVIVOR's
## ledger member grows. Then the gates: a replay, a networked match and a non-growth mode
## award nothing.
##
## Deaths go through Unit.take_damage (the real death path: the owner drops the unit and
## GameEvents.unit_eliminated fires), and the tracker settles itself off that signal exactly
## as it does in a live battle. The players are handed in through the tracker's test seam
## rather than PlayerManager's global list, so no autoload state is touched.
##
## Ledger + inventory are redirected to temp files (tests/README.md rule 4).

const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const LEDGER_PATH := "user://test_evo_growth_live.json"
const ITEMS_PATH := "user://test_evo_growth_live_items.json"
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose (see tests/README.md rule 3).
var _guard

var _human: Player = null
var _enemy: Player = null
var _tracker: GrowthTracker = null


func before_all() -> void:
	RosterLedger.set_save_path(LEDGER_PATH)
	ItemInventory.set_save_path(ITEMS_PATH)


func before_each() -> void:
	# A SOLO battle, so the only gate a test trips is the one it arms.
	_guard = Guard.new()
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	RosterLedger.reset()
	ItemInventory.reset()
	GrowthTracker.begin_battle_log()
	_human = Player.new(0, "You")
	_enemy = Player.new(1, "Grove")
	_enemy.is_ai = true
	_tracker = GrowthTracker.new()
	_tracker.players_override = [_human, _enemy]
	_tracker.squad_override = ["tree_grunt", "vineweave"]
	add_child_autofree(_tracker)
	_tracker.setup()


func after_each() -> void:
	_guard.restore()
	ReplayPlayback.end_playback()
	MatchLoadouts.clear()
	GrowthTracker.begin_battle_log()
	RosterLedger.reset()
	ItemInventory.reset()


func after_all() -> void:
	for path in [LEDGER_PATH, ITEMS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	RosterLedger.set_save_path(RosterLedger.DEFAULT_SAVE_PATH)
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)


func _spawn(id: String, owner: Player) -> Unit:
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = CharacterLibrary.get_character(id)
	add_child_autofree(unit)
	owner.add_unit(unit)
	return unit


## Kill [param unit] through the real death path and let its deferred cleanup unwind.
func _kill(unit: Unit) -> void:
	unit.take_damage(99999)
	await get_tree().process_frame
	await get_tree().process_frame


func _fight_a_small_battle() -> void:
	_spawn("tree_grunt", _human)
	var vine := _spawn("vineweave", _human)
	var foe := _spawn("blightcap", _enemy)
	_tracker.roll_call()  # the turn-start sweep, run by hand
	await _kill(vine)
	await _kill(foe)


func test_a_won_battle_grows_the_survivor_only() -> void:
	_tracker.context_override = { "mode": "skirmish" }
	await _fight_a_small_battle()
	assert_eq(RosterLedger.growth_of("tree_grunt"), 1, "Barkling fought and survived a win: +1 Growth")
	assert_eq(RosterLedger.growth_of("vineweave"), 0, "Vineweave fell: no Growth")
	var rows := GrowthTracker.growth_this_battle()
	assert_eq(rows.size(), 1, "the end screen gets exactly one growth row")
	assert_eq(String(rows[0]["uid"]), "tree_grunt", "for Barkling")
	assert_eq(int(rows[0]["gained"]), 1, "who gained one")
	assert_eq(int(rows[0]["goal"]), RosterLedger.next_growth_goal("tree_grunt"), "towards Oakheart's goal")
	assert_true(FileAccess.file_exists(LEDGER_PATH), "the ledger was saved")


func test_the_battle_settles_once() -> void:
	_tracker.context_override = { "mode": "skirmish" }
	await _fight_a_small_battle()
	assert_false(_tracker.settle(true), "a second settle (the end screen's reveal) awards nothing more")
	GrowthTracker.settle_live(self, true)
	assert_eq(RosterLedger.growth_of("tree_grunt"), 1, "still exactly one Growth")


func test_three_wins_make_barkling_ready_to_evolve() -> void:
	var goal := RosterLedger.next_growth_goal("tree_grunt")
	for i in range(goal):
		var t := GrowthTracker.new()
		t.players_override = [_human, _enemy]
		t.squad_override = ["tree_grunt"]
		t.context_override = { "mode": "skirmish" }
		add_child_autofree(t)
		var bark := _spawn("tree_grunt", _human)
		t.roll_call()
		assert_true(t.settle(true), "win %d awards growth" % (i + 1))
		_human.remove_unit(bark)
	assert_eq(RosterLedger.available_evolutions("tree_grunt").size(), 1,
		"after %d surviving wins Barkling can evolve" % goal)
	assert_true(bool(GrowthTracker.growth_this_battle().back()["ready"]), "and the last row says so")


func test_replay_playback_awards_nothing() -> void:
	ReplayPlayback.begin_playback()
	_tracker.context_override = {}
	assert_eq(GrowthTracker.gate_reason(GrowthTracker.live_context(self), EvolutionRules.current()), "replay",
		"the live gate reads the replay flag (and nothing else is closed)")
	await _fight_a_small_battle()
	assert_eq(RosterLedger.growth_of("tree_grunt"), 0, "a replay being watched never earns growth")
	assert_eq(GrowthTracker.growth_this_battle().size(), 0, "and shows no growth rows")


func test_a_networked_match_awards_nothing() -> void:
	MatchLoadouts.set_local_slot(0)
	_tracker.context_override = {}
	assert_eq(GrowthTracker.gate_reason(GrowthTracker.live_context(self), EvolutionRules.current()), "networked",
		"the live gate reads MatchLoadouts.is_active()")
	await _fight_a_small_battle()
	assert_eq(RosterLedger.growth_of("tree_grunt"), 0, "loadout replication active = network versus: no growth")


func test_arena_and_versus_award_nothing() -> void:
	_tracker.context_override = { "mode": "arena", "arena": true }
	await _fight_a_small_battle()
	assert_eq(RosterLedger.growth_of("tree_grunt"), 0, "an arena round never earns growth")
	var t := GrowthTracker.new()
	t.players_override = [_human, _enemy]
	t.squad_override = ["tree_grunt"]
	t.context_override = { "mode": "versus" }
	add_child_autofree(t)
	t.roll_call()
	assert_false(t.settle(true), "hotseat versus is not a growth mode")


func test_live_context_reads_the_real_gates() -> void:
	var ctx := GrowthTracker.live_context(self)
	assert_eq(String(ctx["mode"]), "skirmish", "a solo battle with no mode controller is a skirmish")
	assert_eq(GrowthTracker.gate_reason(ctx, EvolutionRules.current()), "", "which earns growth")
	assert_false(bool(ctx["replay"]), "no replay is playing in the test run")
	assert_false(bool(ctx["networked"]), "no networked match either")
	ReplayPlayback.begin_playback()
	MatchLoadouts.set_local_slot(0)
	ctx = GrowthTracker.live_context(self)
	assert_true(bool(ctx["replay"]), "ReplayPlayback.is_playing() is read")
	assert_true(bool(ctx["networked"]), "MatchLoadouts.is_active() is read")
