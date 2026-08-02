extends GutTest

## Unit tests for the mid-battle save FORMAT and the save GATE -- everything about
## [BattleSnapshot] / [BattleSaveManager] that can be proved without a live battle.
##
## The three things pinned here each fail silently if they break:
##   1. The snapshot survives a JSON round trip. Every value in it is a JSON primitive
##      ([Vector2i] -> [x, y], [StringName] -> String); a Godot type sneaking in would come
##      back as a String and quietly break the restore rather than raising.
##   2. The runtime clocks -- [MovesetController] cooldowns, [SpawnManager]'s per-point
##      schedule, [HazardManager]'s in-flight vines -- round-trip EXACTLY. None of them is
##      derivable from the board, so a lossy pair is a permanent state loss.
##   3. The save gate excludes networked and Arena battles. Both would resume into a
##      nonsense state (a match that is not this peer's to pause; a round with no run behind
##      it), so the exclusion is tested as a pure decision rather than by standing one up.
##
## No autoload is mutated and nothing is written to disk: the save-path injection is exercised
## in test_battle_save_eod.gd, which is where the file layer belongs.

const SAVE_MANAGER := preload("res://systems/save/BattleSaveManager.gd")


func before_each() -> void:
	# CombatServices is a global autoload: a board left behind by an earlier suite would be
	# consulted by SpawnManager's occupancy guard here, against freed units.
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()


# --- JSON safety ------------------------------------------------------------

func test_a_cell_round_trips_through_json() -> void:
	var encoded: Array = BattleSnapshot.cell_to_array(Vector2i(3, 7))
	assert_eq(encoded, [3, 7], "a cell is stored as a plain [x, y] pair -- JSON has no vectors")
	var text: String = JSON.stringify(encoded)
	assert_eq(BattleSnapshot.array_to_cell(JSON.parse_string(text)), Vector2i(3, 7),
		"and comes back as the same cell after a JSON round trip")


func test_a_malformed_cell_falls_back_instead_of_raising() -> void:
	assert_eq(BattleSnapshot.array_to_cell("nonsense", Vector2i(1, 1)), Vector2i(1, 1),
		"a truncated save degrades to the fallback cell, it never raises")
	assert_eq(BattleSnapshot.array_to_cell([4], Vector2i(2, 2)), Vector2i(2, 2),
		"a half-written pair is treated the same way")


func test_a_whole_snapshot_survives_a_json_round_trip() -> void:
	var snapshot: Dictionary = _fake_snapshot("2026-08-02", BattleSnapshot.MODE_SKIRMISH)
	var restored: Dictionary = BattleSnapshot.from_json(BattleSnapshot.to_json(snapshot))

	assert_true(BattleSnapshot.is_supported(restored), "the round-tripped save is still usable")
	assert_eq(int(restored.get("format_version", -1)), BattleSnapshot.FORMAT_VERSION)
	assert_eq(String(restored.get("saved_at_utc_date", "")), "2026-08-02")
	var units: Array = restored.get("units", [])
	assert_eq(units.size(), 1, "the unit list survives")
	assert_eq(BattleSnapshot.array_to_cell((units[0] as Dictionary).get("cell", [])), Vector2i(2, 3),
		"a unit's cell comes back as the cell it was standing on")
	assert_eq(int((units[0] as Dictionary).get("hp", -1)), 11,
		"current HP is the one stat stored, and it comes back unchanged")


func test_an_unsupported_or_empty_save_is_rejected() -> void:
	assert_false(BattleSnapshot.is_supported({}), "no file means nothing to resume")
	assert_false(BattleSnapshot.is_supported({"format_version": 99, "context": {}, "units": [{}]}),
		"a future format version is refused rather than half-restored")
	assert_false(BattleSnapshot.is_supported({"format_version": BattleSnapshot.FORMAT_VERSION,
		"context": {}, "units": []}), "a battle with no units is not a battle")
	assert_eq(BattleSnapshot.from_json("not json at all"), {},
		"unparseable text reads as 'no usable save'")


# --- Move cooldowns ---------------------------------------------------------

func test_move_cooldowns_and_charges_round_trip() -> void:
	var source: MovesetController = autofree(MovesetController.new())
	var move := MoveResource.new()
	move.move_id = &"thorn_lash"
	move.cooldown = 3
	move.max_uses = 2
	source.on_used(move)

	assert_eq(source.remaining(move), 3, "the move is on a 3-turn cooldown")
	assert_eq(source.uses_left(move), 1, "and has spent one of its two charges")

	var state: Dictionary = source.snapshot_state()
	var text: String = JSON.stringify(state)  # the save goes through JSON, so the test does too
	var target: MovesetController = autofree(MovesetController.new())
	target.restore_state(JSON.parse_string(text))

	assert_eq(target.remaining(move), 3, "the REMAINING cooldown is restored, not the full one")
	assert_eq(target.uses_left(move), 1, "and the spent charge is still spent")
	assert_false(target.can_use(move), "so the move is still unavailable after a resume")


func test_a_ready_move_stores_nothing() -> void:
	var controller: MovesetController = autofree(MovesetController.new())
	var state: Dictionary = controller.snapshot_state()
	assert_eq((state.get("cooldowns", {}) as Dictionary).size(), 0,
		"a move that is ready needs no entry -- the file stays small")


# --- Spawn scheduler --------------------------------------------------------

func test_the_spawn_schedule_clock_round_trips() -> void:
	var manager: SpawnManager = autofree(SpawnManager.new())
	var map := _endless_map()
	manager.initialize(null, map)
	manager.process_turn()
	manager.process_turn()

	var state: Dictionary = manager.snapshot_state()
	assert_eq(int(state.get("current_turn", -1)), 2, "the per-turn clock is captured")

	var target: SpawnManager = autofree(SpawnManager.new())
	target.initialize(null, map)
	target.restore_state(JSON.parse_string(JSON.stringify(state)))
	assert_eq(target.snapshot_state(), state,
		"a schedule restored from a snapshot re-emits exactly the same snapshot")


# --- In-flight hazards ------------------------------------------------------

func test_a_travelling_hazard_resumes_where_it_stopped() -> void:
	var manager: HazardManager = autofree(HazardManager.new())
	var hazard := TravelingHazard.new(Vector2i(2, 2), Vector2i(0, 1), 1, 2, 6, 7,
		CombatTypes.DamageCategory.PHYSICAL, CombatTypes.TargetKind.ENEMY, null)
	manager.register(hazard)
	manager.process_turn()  # crawls two rows forward

	var state: Dictionary = manager.snapshot_state(func(_u): return -1)
	var target: HazardManager = autofree(HazardManager.new())
	target.restore_state(JSON.parse_string(JSON.stringify(state)), func(_i): return null)

	assert_eq(target.active_count(), 1, "the vine is still travelling after a resume")
	var resumed: Dictionary = target.snapshot_state(func(_u): return -1)
	var before: Dictionary = (state.get("hazards", [])[0] as Dictionary)
	var after: Dictionary = (resumed.get("hazards", [])[0] as Dictionary)
	assert_eq(int(after.get("front", -1)), int(before.get("front", -2)),
		"it picks up from the row it had already reached, not from its origin")
	assert_eq(int(after.get("remaining", -1)), int(before.get("remaining", -2)),
		"with the same travel left to run")


func test_an_expired_hazard_is_not_saved() -> void:
	var manager: HazardManager = autofree(HazardManager.new())
	manager.register(TravelingHazard.new(Vector2i.ZERO, Vector2i(1, 0), 0, 2, 0, 5,
		CombatTypes.DamageCategory.PHYSICAL, CombatTypes.TargetKind.ENEMY, null))
	var state: Dictionary = manager.snapshot_state(func(_u): return -1)
	assert_eq((state.get("hazards", []) as Array).size(), 0,
		"a vine that has finished its lane is not carried into the save")


# --- The save gate ----------------------------------------------------------

func test_a_solo_battle_in_progress_can_be_saved() -> void:
	assert_true(SAVE_MANAGER.gate(true, false, false, true, true, true),
		"a solo battle in progress with a live board is exactly what this feature is for")


func test_a_networked_match_can_never_be_saved() -> void:
	assert_false(SAVE_MANAGER.gate(true, true, false, true, true, true),
		"a networked battle is not this peer's to pause")


func test_an_arena_round_can_never_be_saved() -> void:
	assert_false(SAVE_MANAGER.gate(true, false, true, true, true, true),
		"an Arena round's real state lives in the run, not on the board")


func test_versus_and_pre_battle_states_are_excluded() -> void:
	assert_false(SAVE_MANAGER.gate(false, false, false, true, true, true),
		"a hot-seat / versus match has no single owner to hand the battle back to")
	assert_false(SAVE_MANAGER.gate(true, false, false, false, true, true),
		"there is nothing to save before the battle starts")
	assert_false(SAVE_MANAGER.gate(true, false, false, true, false, true),
		"nor without an active turn system")
	assert_false(SAVE_MANAGER.gate(true, false, false, true, true, false),
		"nor once the player has no units left standing")


# --- Banner text ------------------------------------------------------------

func test_the_banner_names_the_mode_the_map_and_the_date() -> void:
	var text: String = SAVE_MANAGER.describe(_fake_snapshot("2026-08-02", BattleSnapshot.MODE_CHALLENGE))
	assert_true(text.contains("CHALLENGE"), "the banner says which mode is waiting")
	assert_true(text.contains("Proving Grounds"), "and which map it is on")
	assert_true(text.contains("2026-08-02"), "and when it was saved")


func test_describe_falls_back_to_the_map_file_name() -> void:
	var snapshot: Dictionary = _fake_snapshot("2026-08-02", BattleSnapshot.MODE_SKIRMISH)
	(snapshot["context"] as Dictionary)["map_name"] = ""
	assert_true(SAVE_MANAGER.describe(snapshot).contains("proving_grounds"),
		"a save written before the map had a name still labels itself")


# --- Fixtures ---------------------------------------------------------------

func _fake_snapshot(date: String, mode: String) -> Dictionary:
	return {
		"format_version": BattleSnapshot.FORMAT_VERSION,
		"saved_at_utc_date": date,
		"saved_at_utc": date + "T12:00:00",
		"context": {
			"mode": mode,
			"map_path": "res://game/maps/resources/proving_grounds.tres",
			"map_name": "Proving Grounds",
			"campaign_chapter_id": "",
			"campaign_turns": 0,
			"challenge_id": "",
			"challenge": {},
			"challenge_turns": 0,
			"challenge_units_lost": 0,
			"squad": ["vineweave"],
			"turn_system": 0,
			"player_count": 2,
			"difficulty": 1,
		},
		"units": [{
			"index": 0,
			"character_id": "vineweave",
			"player_id": 0,
			"cell": BattleSnapshot.cell_to_array(Vector2i(2, 3)),
			"hp": 11,
			"shield": 0,
			"facing_yaw": 0.0,
			"has_acted": false,
			"has_moved": false,
			"provoked": false,
			"extra_actions": 0,
			"ai_stance": "defensive",
			"home_cell": BattleSnapshot.cell_to_array(Vector2i(2, 3)),
			"aggro_range": -1,
			"leash_radius": -1,
			"statuses": [{"id": "rubble_slowed", "turns_left": 1}],
			"moves": {"cooldowns": {}, "uses_spent": {}},
		}],
		"turn": {
			"type": BattleSnapshot.TURN_TRADITIONAL,
			"current_turn": 4,
			"round_number": 4,
			"current_player_id": 0,
			"acted": [],
			"players_had_turn": [0],
		},
		"board": {"applied_tile_effects": [], "spawn_manager": {}, "hazard_manager": {}},
	}


## A minimal map with one ENDLESS spawn point, which is all SpawnManager needs to build a
## schedule it can then tick. No board, no autoloads -- initialize()/process_turn() are the
## seam that exists precisely for this.
func _endless_map() -> MapResource:
	var map := MapResource.new()
	map.width = 5
	map.height = 5
	map.max_players = 2
	map.create_default_layout()
	map.set_spawn_point_at_position(Vector2i(1, 1), 1, MapResource.SPAWN_KIND_ENDLESS, {
		"character_id": "vineweave",
		"respawn_interval": 2,
	})
	return map
