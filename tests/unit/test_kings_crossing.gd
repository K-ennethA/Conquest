extends GutTest

## Invariants for the King's Crossing base-assault map and the "bastion" structure it
## fields. Guards the things the MODE depends on -- both bases present, both sides given
## a respawn point and an endless grunt portal, the neutral guardian camp on slot 2, and
## the objective string that compiles to [DestroyBase] -- without pinning cosmetics.

const MAP_PATH := "res://game/maps/resources/kings_crossing.tres"
const BASE_ID := "bastion"
## Mirrors PlayerManager.NEUTRAL_PLAYER_INDEX (and ArenaRoundBuilder.NEUTRAL_PLAYER_ID):
## the fixed slot the neutral faction always occupies.
const NEUTRAL_SLOT: int = 2

var _map: MapResource


func before_all() -> void:
	_map = load(MAP_PATH) as MapResource


## Compiling this map's rules ARMS the shared BaseAssaultRuntime singleton (production
## wiring); silence it again so it cannot observe another suite's events.
func after_all() -> void:
	BaseAssaultRuntime.sync(null)


## Every spawn entry for [param player_id], normalized (so the optional keys are filled).
func _spawns_for(player_id: int) -> Array:
	var out: Array = []
	for sd in _map.unit_spawns:
		if int(sd.get("player_id", -1)) == player_id:
			out.append(_map.normalize_spawn(sd))
	return out


func _kinds_for(player_id: int) -> Dictionary:
	var counts: Dictionary = {}
	for sd in _spawns_for(player_id):
		var kind: String = String(sd["spawn_kind"])
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


# --- Identity ----------------------------------------------------------------

func test_map_loads_and_is_offered_to_players() -> void:
	assert_not_null(_map, "King's Crossing map resource should load")
	assert_eq(_map.map_name, "King's Crossing")
	assert_eq(_map.width, 13)
	assert_eq(_map.height, 11)
	assert_true(_map.is_active(), "must be Active so it lists in the Skirmish map picker")


func test_declares_three_player_slots_for_the_neutral_faction() -> void:
	# MapLoader builds one container per max_players slot; the neutrals live on slot 2,
	# so a 2-player declaration would leave them homeless.
	assert_gte(_map.max_players, 3, "the neutral faction needs a third slot")


# --- Terrain -----------------------------------------------------------------

func test_every_cell_is_painted_and_resolves() -> void:
	assert_eq(_map.tile_layout.size(), _map.width * _map.height, "every cell painted")
	var composition: Dictionary = {}
	for tile in _map.tile_layout:
		var tid: String = str(tile.get("tile_id", ""))
		composition[tid] = int(composition.get(tid, 0)) + 1
		assert_not_null(TileCatalog.find_by_id(StringName(tid)),
			"tile_id '%s' must resolve via TileCatalog" % tid)
	assert_gt(int(composition.get("sacred_ground", 0)), 0, "the contested hill is fortifying ground")
	assert_gt(int(composition.get("tall_grass", 0)), 0, "the hill is ringed with cover")
	assert_gt(int(composition.get("grass_plains", 0)), 0, "has open ground to cross")


func test_the_hill_sits_between_the_two_bases() -> void:
	var hill_x: Array = []
	for tile in _map.tile_layout:
		if str(tile.get("tile_id", "")) == "sacred_ground":
			hill_x.append(int(tile.get("position", Vector2i(-1, -1)).x))
	assert_false(hill_x.is_empty(), "there is a hill")
	var bases: Dictionary = {}
	for sd in _map.unit_spawns:
		if str(sd.get("character_id", "")) == BASE_ID:
			bases[int(sd.get("player_id", -1))] = int(sd.get("position", Vector2i(-1, -1)).x)
	assert_true(bases.has(0) and bases.has(1), "both bases placed")
	var lo: int = mini(int(bases[0]), int(bases[1]))
	var hi: int = maxi(int(bases[0]), int(bases[1]))
	for hx in hill_x:
		assert_true(int(hx) > lo and int(hx) < hi, "hill cell %d lies between the bases" % int(hx))


# --- The two bases -------------------------------------------------------------

func test_both_sides_field_exactly_one_base() -> void:
	var bases: Dictionary = {}
	for sd in _map.unit_spawns:
		if str(sd.get("character_id", "")) == BASE_ID:
			var pid: int = int(sd.get("player_id", -1))
			bases[pid] = int(bases.get(pid, 0)) + 1
	assert_eq(int(bases.get(0, 0)), 1, "the player has one base")
	assert_eq(int(bases.get(1, 0)), 1, "the enemy has one base")
	assert_eq(bases.size(), 2, "nobody else owns a base -- least of all the neutrals")


func test_the_bases_are_placed_at_load_and_never_come_back() -> void:
	for sd in _map.unit_spawns:
		if str(sd.get("character_id", "")) != BASE_ID:
			continue
		var norm: Dictionary = _map.normalize_spawn(sd)
		assert_true(_map.is_initial_spawn(sd), "a base stands from turn one")
		assert_eq(int(norm["max_spawns"]), 1, "a destroyed base must NOT respawn")
		# NOT a "Start" point: Start points are the squad slots Character Select fills,
		# and a base overwritten by a squad pick would break the whole mode
		# (see MapLoader._load_units).
		assert_ne(String(norm["spawn_kind"]), MapResource.SPAWN_KIND_START,
			"the base must not sit in a squad slot")


func test_the_player_keeps_squad_slots_for_character_select() -> void:
	var kinds: Dictionary = _kinds_for(0)
	assert_gt(int(kinds.get(MapResource.SPAWN_KIND_START, 0)), 0,
		"the player still picks a squad")


# --- Reinforcement economy ------------------------------------------------------

func test_both_sides_get_a_respawn_point_and_an_endless_grunt_portal() -> void:
	for pid in [0, 1]:
		var kinds: Dictionary = _kinds_for(pid)
		assert_gt(int(kinds.get(MapResource.SPAWN_KIND_RESPAWN, 0)), 0,
			"player %d has a respawn point" % pid)
		assert_gt(int(kinds.get(MapResource.SPAWN_KIND_ENDLESS, 0)), 0,
			"player %d has an endless grunt portal" % pid)


func test_the_spawners_are_symmetric_and_paced() -> void:
	var p0: Array = _spawns_for(0)
	var p1: Array = _spawns_for(1)
	assert_eq(p0.size(), p1.size(), "both sides get the same number of spawn points")
	for sd in p0 + p1:
		var kind: String = String(sd["spawn_kind"])
		if kind != MapResource.SPAWN_KIND_RESPAWN and kind != MapResource.SPAWN_KIND_ENDLESS:
			continue
		assert_gte(int(sd["respawn_interval"]), 2, "waves are staggered, not one-per-turn")
		assert_eq(int(sd["max_spawns"]), -1, "a portal is unbounded")


# --- Neutral guardians -----------------------------------------------------------

func test_neutral_guardians_hold_the_hill_and_come_back() -> void:
	var neutrals: Array = _spawns_for(NEUTRAL_SLOT)
	assert_gte(neutrals.size(), 1, "the hill is guarded")
	assert_lte(neutrals.size(), 2, "1-2 guardians, not an army")
	for sd in neutrals:
		assert_eq(String(sd["spawn_kind"]), MapResource.SPAWN_KIND_RESPAWN,
			"a guardian camp regrows")
		assert_eq(int(sd["leash_radius"]), 0, "a guardian never leaves its post")
		var character := CharacterLibrary.get_character(String(sd["character_id"]))
		assert_not_null(character, "guardian character resolves")
		# MapLoader's difficulty gate silently drops any non-player unit whose character
		# demands a harder setting -- an objective that vanishes on Normal is no objective.
		assert_eq(character.get_min_difficulty(), 0, "a guardian must spawn at every difficulty")


# --- Objective + validation --------------------------------------------------------

func test_the_map_declares_the_base_assault_objective() -> void:
	assert_eq(_map.victory_conditions.size(), 1, "exactly one objective")
	assert_eq(String(_map.victory_conditions[0]), "Destroy Enemy Base",
		"the objective is: destroy the enemy base")


func test_the_objective_compiles_to_a_destroy_base_rule_set() -> void:
	var rules := WinConditionLibrary.build_rules(_map.victory_conditions, 0)
	assert_eq(rules.win_conditions.size(), 1, "one compiled objective")
	assert_true(rules.win_conditions[0] is DestroyBase, "compiles to DestroyBase")


func test_every_spawn_character_resolves() -> void:
	for sd in _map.unit_spawns:
		var cid: String = str(sd.get("character_id", ""))
		assert_false(cid.is_empty(), "every spawn point on this map names what it fields")
		assert_not_null(CharacterLibrary.get_character(cid),
			"spawn character '%s' must resolve" % cid)


func test_map_passes_its_own_strict_validator() -> void:
	var report: Dictionary = _map.validate_map(true)
	assert_true(report.get("valid", false),
		"strict validation issues: %s" % str(report.get("issues", [])))


# --- The bastion structure ------------------------------------------------------

func test_bastion_loads_and_is_immobile() -> void:
	var bastion := CharacterLibrary.get_character(BASE_ID)
	assert_not_null(bastion, "the bastion character resolves")
	assert_eq(String(bastion.character_id), BASE_ID)
	assert_eq(bastion.base_movement, 0, "a base does not walk")
	assert_eq(bastion.get_default_leash_radius(), 0, "and is anchored on top of that")
	assert_gte(bastion.base_health, 150, "a base soaks a real assault")
	assert_gt(bastion.base_defense, bastion.base_attack, "defensive, not a duellist")


func test_bastion_is_not_a_boss() -> void:
	# is_boss would make every "Defeat Boss" map that ever fields one winnable by
	# accident -- the base is scored by DestroyBase alone.
	assert_false(CharacterLibrary.get_character(BASE_ID).is_boss, "a base is not a boss")


func test_bastion_has_a_valid_non_empty_moveset() -> void:
	var bastion := CharacterLibrary.get_character(BASE_ID)
	var report: Dictionary = bastion.validate()
	assert_true(report.get("valid", false), "character issues: %s" % str(report.get("issues", [])))
	assert_gt(bastion.move_count(), 0, "an empty moveset leaves the AI/UI with nothing to offer")
	for i in range(bastion.move_count()):
		var move := bastion.get_move(i)
		assert_not_null(move, "move slot %d is filled" % i)
		assert_not_null(move.targeting, "move '%s' has a targeting pattern" % String(move.move_id))
		assert_eq(move.targeting.max_range, 0, "a base only ever acts on itself")


func test_bastion_fits_one_cell() -> void:
	assert_eq(CharacterLibrary.get_character(BASE_ID).get_footprint(), Vector2i.ONE,
		"1x1 -- the map places bases on single cells")
