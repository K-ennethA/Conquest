extends Node
class_name SiegeController

## The runtime a SIEGE map needs on top of its [CaptureBase] win condition -- the mode's
## whole moving part. Owned by the mode layer, armed and disarmed from
## [method WinConditionLibrary.build_rules], and completely INERT on every other map.
##
## SHAPE. Deliberately the same shape [BaseAssaultRuntime] takes for King of the Hill: a
## lazily-installed singleton parented to the scene-tree root, armed when the compiled rules
## carry this mode's objective and silenced otherwise, with arming RESETTING every per-battle
## latch so a second battle in the same app run starts clean. Everything Siege adds that KotH
## already solved is REUSED rather than rebuilt:
##
##   * runtime spawning + ADOPTION -- [method SpawnManager.spawn_and_adopt], the one entry
##     point that gives a mid-battle unit an owner and a place in the turn order
##     (CONQUEST.md rule 4). Creep waves and squad respawns both go through it, so neither
##     grows its own copy of the adoption discipline;
##   * per-turn timing -- the ACTIVE turn system's turn_started / turn_ended (CONQUEST.md
##     rule 2), never PlayerManager's, which do not fire on AI turns;
##   * AI -- [BotController]'s existing planner, entered through a MARCH stance (a lane
##     stamped on the creep) rather than a second decision engine;
##   * the win flow -- a completed capture re-enters [code]GameWorldManager[/code]'s ordinary
##     end-of-battle evaluation, which scores [CaptureBase] like any other objective.
##
## THE FOUR JOBS.
##
## 1. THE ROUND CLOCK. Waves and respawns are measured in full ROUNDS, which neither turn
##    system exposes the same way (Traditional counts player switches in `current_turn`;
##    Speed First keeps `round_number`). So the round is DERIVED per system and then
##    EDGE-DETECTED into this node's own counter: what the cadence actually runs on is "how
##    many round boundaries have I observed", which is identical on every peer stepping the
##    same turn signals and needs no agreement about absolute numbering.
##
## 2. CREEP WAVES. Every [member SiegeRuleset.wave_every_rounds] rounds each side pushes
##    [member SiegeRuleset.creeps_per_lane] creeps down every lane, from that side's END of
##    the lane, up to a per-side live cap. NOTHING here is rolled: the roster is cycled by a
##    running index and the cells come straight off the authored waypoints, so two peers
##    spawn the same creeps on the same cells in the same order. Creeps are owned by the SIDE
##    they fight for (so they are its squad's allies -- [code]BoardAdapter.are_enemies[/code]
##    keys purely on owner, so an "ally AI" player would have made a side's own creeps its
##    enemies) and marked AI-driven, which is what makes [BotTurnDriver] resolve them during
##    their owner's turn even when that owner is the human.
##
## 3. SQUAD RESPAWNS. A fallen squad unit returns at its own base cell at FULL HP with NO
##    statuses -- both of which come free from spawning a fresh unit -- carrying the move
##    cooldowns it died holding, after a wait that ESCALATES with how late in the match it
##    fell ([method SiegeRuleset.respawn_delay_for_round]). The wait is computed from the
##    DEATH round and then frozen on the queue entry, so an early death stays cheap even if
##    the unit is still queued much later, and no queued respawn's remaining time can ever
##    change retroactively. "As at death" is the deliberate cooldown choice: ticking a
##    dead unit's cooldowns would need a clock for units that are not on the board, and
##    clearing them would make dying a way to refresh an ultimate. Respawns run
##    unconditionally, including while a base is mid-capture: a rule that suspended them
##    would make the last seconds of a match the one moment reinforcements stop, which is
##    exactly backwards.
##
## 4. THE CAPTURE STATE MACHINE. See [CaptureBase] for the rule; this owns the latch.
##      * on turn ENDED  -- a hero of the acting side standing on the enemy base cell BEGINS
##        a capture (unit + cell + side recorded);
##      * on turn STARTED -- a pending capture whose unit is still alive and still on that
##        same cell COMPLETES, and its side wins. Anything else cancels it.
##    Under Speed First a "turn" belongs to a UNIT, so both halves are narrowed to the unit
##    actually acting (via the system's `current_acting_unit`); under Traditional a turn
##    belongs to a PLAYER and the whole side is considered. That one branch is the only place
##    the two systems are told apart.
##
## NETWORKING. Nothing here draws a random number, reads wall-clock time, or branches on
## which peer is running: every decision is a function of the authored map, the ruleset, and
## the sequence of turn signals -- which is exactly the input a lockstep peer replays. The
## one gap worth naming is that the spawns are not themselves COMMANDS: they are resolution
## driven off the shared turn stream, so they stay in step, but a mid-match join would have
## to re-derive them rather than read them from the log.

## Node name in the scene-tree root. Must match [constant CaptureBase.CONTROLLER_NODE], which
## is how the win condition finds this latch without a class reference (that would cycle).
const NODE_NAME := "SiegeController"

## Authored ruleset loaded when one exists; otherwise the [SiegeRuleset] defaults are used.
const DEFAULT_RULESET_PATH := "res://game/modes/rulesets/siege_default.tres"

## Spawn kind creeps are materialised as. Reinforcement makes [MapLoader] resolve them
## AGGRESSIVE, which is the right fallback the moment the march branch declines and the creep
## drops into the ordinary planner.
const CREEP_SPAWN_KIND := "Reinforcement"

## The single live instance, or null before the first Siege map.
static var _instance: SiegeController = null

## While false every handler returns immediately -- the node exists but does nothing.
var _armed: bool = false

## Tuning. Never null once armed.
var _ruleset: SiegeRuleset = null

## Lane waypoints as authored: an Array of Arrays of [Vector2i], each ordered from player 0's
## side toward player 1's. Empty on a non-Siege map.
var _lanes: Array = []

## player_id -> capture cell ([Vector2i]).
var _base_cells: Dictionary = {}

## Round boundaries observed this battle (0 before the first turn).
var _rounds_elapsed: int = 0

## The derived round value we last saw, for edge detection.
var _last_seen_round: int = -1

## Running creep index per side: player_id -> int. Feeds the roster cycle, so the creep
## sequence is a pure function of how many that side has already produced.
var _creep_serial: Dictionary = {}

## Pending squad respawns: an Array of Dictionaries
## { "player_id": int, "character_id": String, "round": int, "delay": int, "moves": Dictionary }.
## Read through [method respawn_queue], which adds the live "rounds_remaining".
var _respawn_queue: Array = []

## The capture in flight: {} or { "player_id": int, "unit": Unit, "cell": Vector2i }.
var _capture: Dictionary = {}

## Side that has COMPLETED a capture, or -1. Latched -- a battle is decided once.
var _captured_by: int = -1

## The turn system we are currently listening to (re-wired if it switches).
var _watched_ts = null

## Optional board seam. When null the live board is read off CombatServices; tests inject a
## lightweight fake so the capture machine can run headless. Mirrors
## [code]SpawnManager._board_override[/code].
var _board_override = null

## Optional spawner seam, same contract as [member _board_override]: tests inject a fake with
## a `spawn_and_adopt` method instead of standing up a MapLoader + live board.
var _spawner_override = null


# --- Arming (called from WinConditionLibrary) --------------------------------

## Bring the runtime in line with a freshly compiled [param rules] set: install + arm it when
## the rules contain a [CaptureBase] objective, disarm it otherwise. Returns the live
## instance, or null when there is nothing to do and none exists.
static func sync(rules: GameModeRules) -> SiegeController:
	var wants: bool = _rules_want_runtime(rules) or map_declares_siege()

	if _instance != null and not is_instance_valid(_instance):
		_instance = null

	if _instance == null:
		if not wants:
			return null
		_instance = _install()
		if _instance == null:
			return null

	_instance.set_armed(wants)
	return _instance


## The live instance, or null. Public so the save gate and the HUD can ask without arming
## anything.
static func instance() -> SiegeController:
	if _instance != null and not is_instance_valid(_instance):
		_instance = null
	return _instance


## True when [param rules] carries at least one [CaptureBase] objective.
static func _rules_want_runtime(rules: GameModeRules) -> bool:
	if rules == null:
		return false
	for c in rules.win_conditions:
		if c is CaptureBase:
			return true
	for c in rules.lose_conditions:
		if c is CaptureBase:
			return true
	return false


## True when the LOADED map declares the Siege geometry (lanes + base cells), regardless of
## which objective it named.
##
## Two separate opt-ins, deliberately, because they buy different things:
##   * a map that authors LANES + BASE CELLS gets the mode's RUNTIME -- creep waves, squad
##     respawns, the march AI. That is what the geometry is FOR; a map with three lanes and
##     two fortresses wants creeps pushing down them whatever ends the battle.
##   * a map that also names "Capture Enemy Base" additionally gets the CAPTURE objective
##     ([CaptureBase]) as the way to win. A Siege map that instead names "Destroy Enemy Base"
##     is a perfectly coherent variant: the lanes still push, and the battle ends when a
##     fortress structure falls rather than when a hero holds its cell.
## So arming keys off EITHER, and the win condition keys off the string alone.
static func map_declares_siege() -> bool:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return false
	var gwm = (loop as SceneTree).get_first_node_in_group("game_world_manager")
	if gwm == null or not is_instance_valid(gwm):
		return false
	var loader = gwm.get("map_loader")
	if loader == null or not is_instance_valid(loader):
		return false
	var map = loader.get_current_map() if loader.has_method("get_current_map") else loader.get("current_map")
	if map == null:
		return false
	var lanes_value = map.get("lanes")
	var bases_value = map.get("base_cells")
	return lanes_value is Array and not (lanes_value as Array).is_empty() \
		and bases_value is Dictionary and not (bases_value as Dictionary).is_empty()


## Create the singleton and wire it to the buses. The connections happen BEFORE the node is
## in the tree for the same reason [BaseAssaultRuntime] does it: rules are compiled inside
## the battle scene's own _ready cascade, where adding a child to the root can trip Godot's
## "parent node is busy" guard, while the handlers must already be live.
static func _install() -> SiegeController:
	var node := SiegeController.new()
	node.name = NODE_NAME
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	node._connect_bus()

	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		(loop as SceneTree).root.call_deferred("add_child", node)
	return node


## Arm (or silence) the runtime. Arming RESETS every per-battle latch and re-reads the loaded
## map, so each map load starts a clean battle; disarming leaves the node connected but inert.
func set_armed(value: bool) -> void:
	_armed = value
	if not value:
		return
	_rounds_elapsed = 0
	_last_seen_round = -1
	_creep_serial.clear()
	_respawn_queue.clear()
	_capture.clear()
	_captured_by = -1
	if _ruleset == null:
		_ruleset = load_ruleset()
	if is_inside_tree():
		configure_from_map(_live_map())
	else:
		# Installed THIS frame: [method _install] parents the node with call_deferred (adding
		# a child to the root mid-_ready trips Godot's "parent is busy" guard), so there is no
		# tree to reach the battle's map through yet. Re-read the moment there is.
		call_deferred("_read_live_map")


## Deferred second attempt at reading the map, for the frame the singleton is installed on.
func _read_live_map() -> void:
	if _armed:
		configure_from_map(_live_map())


func is_armed() -> bool:
	return _armed


## True while a Siege battle is actually running -- armed AND the map handed us the two things
## the mode needs. This is the mode's identity for everyone outside it (the save gate, the
## HUD, a mode picker): a map is a Siege map exactly when it authored lanes and base cells and
## asked for the capture objective.
func is_active() -> bool:
	return _armed and not _lanes.is_empty() and not _base_cells.is_empty()


# --- Configuration -----------------------------------------------------------

## Load the authored ruleset if one exists, else the defaults. Never returns null.
static func load_ruleset() -> SiegeRuleset:
	if ResourceLoader.exists(DEFAULT_RULESET_PATH):
		var res = load(DEFAULT_RULESET_PATH)
		if res is SiegeRuleset:
			return res as SiegeRuleset
	return SiegeRuleset.new()


## Read the Siege schema off [param map_resource]: `lanes` (an Array of Arrays of
## [Vector2i], each ordered from player 0's side toward player 1's) and `base_cells` (int
## player_id -> [Vector2i]).
##
## Coded against HAS-CHECKS on purpose. Both fields are OPTIONAL additions to [MapResource]
## owned by the map layer, and both default to empty meaning "not a Siege map", so this
## resolves to an inert controller on a map (or a MapResource build) that does not carry them
## rather than failing. Every waypoint is coerced element-wise -- a JSON-parsed map hands
## back plain Arrays and floats, and a plain Array cannot be assigned to a typed one
## (CONQUEST.md rule 3).
func configure_from_map(map_resource) -> void:
	_lanes = []
	_base_cells = {}
	if map_resource == null:
		return

	var raw_lanes = map_resource.get("lanes")
	if raw_lanes is Array:
		for i in range((raw_lanes as Array).size()):
			# Prefer the map's OWN accessor: it owns the coercion, so a JSON-decoded lane
			# resolves there rather than here (CONQUEST.md rule 3). The element-wise path
			# below is the fallback for a stub / a MapResource build without it.
			var lane: Array = []
			if map_resource.has_method("get_lane"):
				lane = map_resource.get_lane(i)
			else:
				lane = _to_cells((raw_lanes as Array)[i])
			if lane.size() >= 2:
				# Copied into a plain Array: the accessor hands back a TYPED Array[Vector2i]
				# and this one is reversed per side, which a typed array would refuse to
				# hand back to an untyped caller.
				var copy: Array = []
				for cell in lane:
					copy.append(cell)
				_lanes.append(copy)

	var raw_bases = map_resource.get("base_cells")
	if raw_bases is Dictionary:
		for key in (raw_bases as Dictionary):
			var cell: Vector2i = Vector2i(-1, -1)
			if map_resource.has_method("get_base_cell"):
				cell = map_resource.get_base_cell(key)
			else:
				cell = _to_cell((raw_bases as Dictionary)[key])
			if cell.x >= 0 and cell.y >= 0:
				_base_cells[int(key)] = cell


## Inject a ruleset (tests, and a future setup screen). Null restores the authored/default one.
func set_ruleset(p_ruleset: SiegeRuleset) -> void:
	_ruleset = p_ruleset if p_ruleset != null else load_ruleset()


func ruleset() -> SiegeRuleset:
	if _ruleset == null:
		_ruleset = load_ruleset()
	return _ruleset


## Every authored lane, as Arrays of [Vector2i] in player-0-to-player-1 order.
func lanes() -> Array:
	return _lanes.duplicate(true)


## The capture cell [param player_id] must DEFEND, or (-1, -1) when it has none.
func base_cell_for(player_id: int) -> Vector2i:
	return _base_cells.get(player_id, Vector2i(-1, -1))


## The capture cell [param player_id] must TAKE: the other side's base. With exactly two
## bases authored this is unambiguous; with more, the lowest other id wins (stable, and the
## shipped schema only ever carries two).
func enemy_base_cell_for(player_id: int) -> Vector2i:
	var ids: Array = _base_cells.keys()
	ids.sort()
	for id in ids:
		if int(id) != player_id:
			return _base_cells[id]
	return Vector2i(-1, -1)


# --- Bus wiring ---------------------------------------------------------------

func _connect_bus() -> void:
	if TurnSystemManager != null:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated(TurnSystemManager.get_active_turn_system())
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null:
		if GameEvents.has_signal(&"unit_eliminated") \
				and not GameEvents.unit_eliminated.is_connected(handle_unit_eliminated):
			GameEvents.unit_eliminated.connect(handle_unit_eliminated)


## (Re)wire to the ACTIVE turn system when it activates or switches -- the same discipline
## [SpawnManager] and [ObjectiveBanner] follow, and for the same reason (CONQUEST.md rule 2).
func _on_turn_system_activated(ts) -> void:
	if _watched_ts == ts:
		return
	if _watched_ts != null and is_instance_valid(_watched_ts):
		if _watched_ts.turn_started.is_connected(_on_turn_started):
			_watched_ts.turn_started.disconnect(_on_turn_started)
		if _watched_ts.turn_ended.is_connected(_on_turn_ended):
			_watched_ts.turn_ended.disconnect(_on_turn_ended)
	_watched_ts = ts
	# A fresh system is a fresh battle: the round clock starts over.
	_rounds_elapsed = 0
	_last_seen_round = -1
	if ts != null and is_instance_valid(ts):
		if not ts.turn_started.is_connected(_on_turn_started):
			ts.turn_started.connect(_on_turn_started)
		if not ts.turn_ended.is_connected(_on_turn_ended):
			ts.turn_ended.connect(_on_turn_ended)


func _on_turn_started(player) -> void:
	handle_turn_started(player, _watched_ts)


func _on_turn_ended(player) -> void:
	handle_turn_ended(player, _watched_ts)


func _exit_tree() -> void:
	if TurnSystemManager != null \
			and TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.disconnect(_on_turn_system_activated)
	if _watched_ts != null and is_instance_valid(_watched_ts):
		if _watched_ts.turn_started.is_connected(_on_turn_started):
			_watched_ts.turn_started.disconnect(_on_turn_started)
		if _watched_ts.turn_ended.is_connected(_on_turn_ended):
			_watched_ts.turn_ended.disconnect(_on_turn_ended)
	_watched_ts = null


# --- 1. The round clock -------------------------------------------------------

## Rounds observed since the battle began (0 before the first turn starts).
func rounds_elapsed() -> int:
	return _rounds_elapsed


## The round number [param ts] is on, derived per system. Speed First keeps a real
## `round_number`; Traditional's `current_turn` is a running player-switch counter, so a round
## is that divided by the number of players -- the same arithmetic Traditional itself uses to
## drive [code]BattleEffectsManager.advance_round[/code]. Returns 0 for an unusable system, so
## the edge detector simply never fires.
static func system_round(ts) -> int:
	if ts == null or not is_instance_valid(ts):
		return 0
	if "round_number" in ts:
		return int(ts.round_number)
	var turn: int = int(ts.get("current_turn")) if "current_turn" in ts else 0
	if turn <= 0:
		return 0
	var players: int = 1
	if "registered_players" in ts:
		players = maxi(1, (ts.registered_players as Array).size())
	return ((turn - 1) / players) + 1


## Feed the clock a fresh reading and, on a ROUND BOUNDARY, run everything that is measured in
## rounds. Public so a test can step the mode with no live turn system at all.
func observe_round(round_value: int) -> void:
	if not _armed or round_value <= 0:
		return
	if _last_seen_round < 0:
		# First reading of the battle: adopt it without counting a boundary, so a system that
		# starts at round 1 does not immediately look like a round has elapsed.
		_last_seen_round = round_value
		_rounds_elapsed = 1
		_run_round_start()
		return
	if round_value == _last_seen_round:
		return
	_last_seen_round = round_value
	_rounds_elapsed += 1
	_run_round_start()


## Everything that happens on a round boundary, in a fixed order: returns first (a unit that
## is due back is on the board before this round's wave measures the creep cap), then the
## wave. Order is part of the determinism contract -- do not reorder without a test.
func _run_round_start() -> void:
	_process_respawns()
	_process_wave()


# --- 2. Creep waves -----------------------------------------------------------

## True when a wave is due on [param round_index] under the current ruleset.
func wave_due(round_index: int) -> bool:
	if round_index <= 0:
		return false
	if round_index == 1:
		return ruleset().wave_on_first_round
	return round_index % ruleset().wave_cadence() == 0


## The creep character id the [param serial]-th creep a side produces should be. A pure cycle
## over the ruleset's roster: no RNG, so both peers name the same unit for the same slot.
func wave_creep_id(serial: int) -> String:
	var rs: SiegeRuleset = ruleset()
	var pool: PackedStringArray = rs.creep_character_ids
	if pool.is_empty():
		return ""
	return pool[serial % pool.size()]


## Push this round's wave for every side that has a base, if one is due.
func _process_wave() -> void:
	if not is_active() or not wave_due(_rounds_elapsed):
		return
	var sides: Array = _base_cells.keys()
	sides.sort()   # fixed iteration order == fixed spawn order
	for side in sides:
		_push_wave_for(int(side))


## Spawn one wave for [param player_id]: [member SiegeRuleset.creeps_per_lane] creeps at that
## side's end of EVERY lane, truncated by the live cap. Lanes are walked in authored order and
## slots in index order, so the whole sequence is fixed.
func _push_wave_for(player_id: int) -> void:
	var rs: SiegeRuleset = ruleset()
	var per_lane: int = rs.wave_size()
	if per_lane <= 0:
		return
	var cap: int = rs.creep_cap()
	var live: int = live_creep_count(player_id)

	for lane_index in range(_lanes.size()):
		var lane: Array = march_lane_for(player_id, lane_index)
		if lane.size() < 2:
			continue
		for i in range(per_lane):
			if cap >= 0 and live >= cap:
				return
			if _spawn_creep(player_id, lane) != null:
				live += 1


## The lane at [param lane_index] in [param player_id]'s MARCH order. Lanes are authored from
## player 0's side toward player 1's, so player 0 walks the array as-is and every other side
## walks it reversed -- which also makes lane[0] that side's spawn end.
func march_lane_for(player_id: int, lane_index: int) -> Array:
	if lane_index < 0 or lane_index >= _lanes.size():
		return []
	var lane: Array = (_lanes[lane_index] as Array).duplicate()
	if player_id != 0:
		lane.reverse()
	return lane


## Materialise ONE creep for [param player_id] at the head of [param lane] and stamp it: the
## march lane + aggro radius the AI planner reads, the AI-driven mark that makes
## [BotTurnDriver] resolve it on its owner's turn, and the creep mark that bars it from ever
## capturing a base. Returns the new unit, or null when it could not be placed.
func _spawn_creep(player_id: int, lane: Array):
	var spawner = _spawn_manager()
	if spawner == null or not spawner.has_method("spawn_and_adopt"):
		return null

	var serial: int = int(_creep_serial.get(player_id, 0))
	var character_id: String = wave_creep_id(serial)
	if character_id.is_empty():
		return null

	var unit = spawner.spawn_and_adopt({
		"position": lane[0],
		"player_id": player_id,
		"character_id": character_id,
		"spawn_kind": CREEP_SPAWN_KIND,
		"ai_stance": "aggressive",
	}, player_id, serial)
	if unit == null:
		return null

	_creep_serial[player_id] = serial + 1
	stamp_creep(unit, lane, ruleset().creep_aggro_radius)
	return unit


## Apply the three marks that make a spawned unit a CREEP. Static + public so a test can build
## one without a live spawner, and so the marks live in exactly one place.
static func stamp_creep(unit, lane: Array, aggro: int) -> void:
	if unit == null or not is_instance_valid(unit) or not unit.has_method("set_meta"):
		return
	unit.set_meta(BotController.MARCH_LANE_META, lane)
	unit.set_meta(BotController.MARCH_AGGRO_META, aggro)
	BotTurnDriver.mark_ai_driven(unit)
	CaptureBase.mark_creep(unit)


## How many living creeps [param player_id] currently fields.
func live_creep_count(player_id: int) -> int:
	var count: int = 0
	for u in _units_of(player_id):
		if not CaptureBase.is_creep(u):
			continue
		if u.has_method("is_alive") and not u.is_alive():
			continue
		count += 1
	return count


# --- 3. Squad respawns --------------------------------------------------------

## Pending respawns, newest last -- THE respawn-HUD contract.
##
## Each entry is a plain Dictionary carrying:
##   "player_id"        int      -- whose unit it is
##   "character_id"     String   -- which roster character is coming back
##   "round"            int      -- the round it died on
##   "delay"            int      -- the escalating wait it was assigned AT DEATH, in rounds
##   "rounds_remaining" int      -- how many more round boundaries until it lands (0 = due now)
##   "moves"            Dictionary -- the cooldowns it will return holding (internal)
##
## "delay" and "rounds_remaining" are the REAL computed numbers the mode runs on, not a copy
## of a ruleset default, so a countdown drawn from them can never disagree with when the unit
## actually returns. A deep copy, so a reader cannot edit the live queue.
func respawn_queue() -> Array:
	var out: Array = []
	for entry in _respawn_queue:
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		copy["rounds_remaining"] = _rounds_remaining_for(entry)
		out.append(copy)
	return out


## [method respawn_queue] filtered to one side -- what a per-side HUD panel wants.
func pending_respawns(player_id: int) -> Array:
	var out: Array = []
	for entry in respawn_queue():
		if int((entry as Dictionary)["player_id"]) == player_id:
			out.append(entry)
	return out


## Rounds still to wait for [param entry], floored at 0.
func _rounds_remaining_for(entry: Dictionary) -> int:
	var waited: int = _rounds_elapsed - int(entry["round"])
	return maxi(0, int(entry["delay"]) - waited)


## Record a fallen SQUAD unit so it can be returned. Creeps and neutrals are skipped: a creep
## is replaced by the next wave, and a neutral belongs to nobody. Public: it is the
## [signal GameEvents.unit_eliminated] handler AND the seam a test drives a death through.
func handle_unit_eliminated(unit, _eliminator = null) -> void:
	if not _armed or unit == null:
		return
	# A death cancels a capture that unit was making -- checked again at completion, but
	# cleared here too so the objective banner stops claiming a capture is in flight.
	if not _capture.is_empty() and _capture.get("unit") == unit:
		_capture.clear()
	if not is_active():
		return
	if not ruleset().respawn_enabled:
		return
	if CaptureBase.is_creep(unit) or CaptureBase.is_neutral(unit):
		return

	var player_id: int = _player_id_of(unit)
	if player_id < 0 or base_cell_for(player_id) == Vector2i(-1, -1):
		return
	var character_id: String = _character_id_of(unit)
	if character_id.is_empty():
		return

	_respawn_queue.append({
		"player_id": player_id,
		"character_id": character_id,
		"round": _rounds_elapsed,
		# The wait is computed HERE, from the round the unit died, and then never recomputed.
		# That is what makes an escalating timer both deterministic and fair: a unit that fell
		# on round 5 keeps round 5's short wait even if it is still queued on round 12.
		"delay": ruleset().respawn_delay_for_round(_rounds_elapsed),
		# Cooldowns AS AT DEATH (see the class docs for why this is the shipped choice).
		# Captured now, while the node is still valid.
		"moves": _capture_moves(unit),
	})


## Return every queued unit whose delay has elapsed, at its own base cell.
func _process_respawns() -> void:
	if not is_active() or _respawn_queue.is_empty():
		return
	var still_waiting: Array = []
	for entry in _respawn_queue:
		# The entry's OWN delay, stamped when it died -- never the ruleset's current answer.
		if _rounds_remaining_for(entry) > 0:
			still_waiting.append(entry)
			continue
		if not _return_unit(entry):
			# Could not be placed this round (base cell and its whole neighbourhood full).
			# Keep it queued so it lands as soon as there is room, rather than vanishing.
			still_waiting.append(entry)
	_respawn_queue = still_waiting


## Spawn one queued entry back at its owner's base. Full HP and no statuses are inherent to a
## fresh unit; only the cooldowns are carried over.
func _return_unit(entry: Dictionary) -> bool:
	var spawner = _spawn_manager()
	if spawner == null or not spawner.has_method("spawn_and_adopt"):
		return false
	var player_id: int = int(entry["player_id"])
	var cell: Vector2i = base_cell_for(player_id)
	if cell == Vector2i(-1, -1):
		return false

	var unit = spawner.spawn_and_adopt({
		"position": cell,
		"player_id": player_id,
		"character_id": String(entry["character_id"]),
		"spawn_kind": MapResource.SPAWN_KIND_START,
	}, player_id, 0)
	if unit == null:
		return false

	_restore_moves(unit, entry.get("moves", {}))
	return true


static func _capture_moves(unit) -> Dictionary:
	if unit == null or not is_instance_valid(unit) or not unit.has_method("get_moveset_controller"):
		return {}
	var controller = unit.get_moveset_controller()
	if controller == null or not controller.has_method("snapshot_state"):
		return {}
	return controller.snapshot_state()


func _restore_moves(unit, state) -> void:
	if not ruleset().respawn_keeps_cooldowns:
		return
	if unit == null or not (state is Dictionary) or (state as Dictionary).is_empty():
		return
	if not unit.has_method("get_moveset_controller"):
		return
	var controller = unit.get_moveset_controller()
	if controller != null and controller.has_method("restore_state"):
		controller.restore_state(state as Dictionary)


# --- 4. The capture state machine ---------------------------------------------

## Side that has COMPLETED a capture, or -1.
func captured_by() -> int:
	return _captured_by


## Side currently mid-capture, or -1.
func capturing_by() -> int:
	if _capture.is_empty():
		return -1
	return int(_capture["player_id"])


## The capture in flight, as a copy ({} when none). Keys: player_id, unit, cell.
func capture_state() -> Dictionary:
	return _capture.duplicate()


## A turn STARTS: resolve a pending capture belonging to this side. Also the round clock's
## reading point -- turn starts are what both turn systems emit for every player, human and AI.
func handle_turn_started(player, ts = null) -> void:
	if not _armed:
		return
	observe_round(system_round(ts))
	if _captured_by >= 0 or _capture.is_empty():
		return
	var side: int = _player_id_of_player(player)
	if side < 0 or side != int(_capture["player_id"]):
		return
	# Speed First: a turn belongs to a UNIT, so only the capturing unit's OWN next turn
	# resolves it. Traditional has no acting unit and the side's turn is the unit's turn.
	var acting = _acting_unit(ts)
	if acting != null and acting != _capture["unit"]:
		return
	_resolve_capture()


## A turn ENDS: a hero of this side standing on the enemy base cell begins a capture.
func handle_turn_ended(player, ts = null) -> void:
	if not _armed or _captured_by >= 0 or not is_active():
		return
	var side: int = _player_id_of_player(player)
	if side < 0:
		return
	var target: Vector2i = enemy_base_cell_for(side)
	if target == Vector2i(-1, -1):
		return

	# Narrow to the acting unit under Speed First; consider the whole side under Traditional.
	var candidates: Array = []
	var acting = _acting_unit(ts)
	if acting != null:
		candidates.append(acting)
	else:
		candidates = _units_of(side)

	for unit in candidates:
		if not CaptureBase.is_capturing_hero(unit, side):
			continue
		if _cell_of(unit) != target:
			continue
		_capture = { "player_id": side, "unit": unit, "cell": target }
		return

	# Nobody in this sample is holding the cell. Cancel a capture in flight ONLY when this
	# sample can actually speak for it: under Traditional the sample is the whole side, so it
	# can; under Speed First it is one unit's turn, and some OTHER unit ending its turn says
	# nothing about whether the holder is still standing on the base.
	if _capture.is_empty() or int(_capture["player_id"]) != side:
		return
	if acting != null and acting != _capture["unit"]:
		return
	_capture.clear()


## Finish (or cancel) the pending capture. The re-check here is the authoritative one: death
## and displacement both show up as "the unit is not alive on that cell any more".
func _resolve_capture() -> void:
	var unit = _capture.get("unit")
	var cell: Vector2i = _capture.get("cell", Vector2i(-1, -1))
	var side: int = int(_capture.get("player_id", -1))
	_capture.clear()

	if side < 0 or not CaptureBase.is_capturing_hero(unit, side):
		return
	if _cell_of(unit) != cell:
		return

	_captured_by = side
	_announce_result()


## Hand the finished capture to the ordinary end-of-battle evaluation, so [CaptureBase] is
## scored exactly like every other objective and the normal victory / defeat screen is what
## the player sees.
##
## Reached through the battle's [code]GameWorldManager[/code] by GROUP, the same way the
## campaign/challenge controllers and the objective banner reach the runtime without editing
## it -- but through its PUBLIC [code]request_game_end_evaluation()[/code], which exists
## precisely because a capture is the first objective in the game that resolves on a turn
## boundary instead of on a death.
##
## DEFERRED because this runs inside the turn system's own turn_started cascade: showing the
## end screen (which pauses and tears down) from there would fire the rest of that turn's
## handlers against a half-dismantled tree. The same reason ArenaController's round hand-off
## is deferred.
func _announce_result() -> void:
	var tree: SceneTree = _tree()
	if tree == null:
		return
	var gwm = tree.get_first_node_in_group("game_world_manager")
	if gwm == null or not is_instance_valid(gwm):
		return
	if gwm.has_method("request_game_end_evaluation"):
		gwm.call_deferred("request_game_end_evaluation")


# --- Shared helpers -----------------------------------------------------------

## The unit whose turn it is, when the turn system is unit-scoped (Speed First). Null under
## Traditional, whose turns belong to a player.
static func _acting_unit(ts):
	if ts == null or not is_instance_valid(ts):
		return null
	if not ("current_acting_unit" in ts):
		return null
	var unit = ts.current_acting_unit
	if unit == null or not is_instance_valid(unit):
		return null
	return unit


## Every living unit belonging to [param player_id].
##
## Read off the BOARD first -- the same source every [WinCondition] is scored against, so the
## mode can never disagree with the objective about who is standing where -- and only through
## [PlayerManager] when there is no board with an `all_units` hook. (The board is also the
## seam tests inject, which is what lets the whole mode run headless.)
func _units_of(player_id: int) -> Array:
	var out: Array = []
	var board = _board_override
	if board == null and CombatServices != null:
		board = CombatServices.board()
	if board != null and board.has_method("all_units"):
		for u in board.all_units():
			if u != null and is_instance_valid(u) and _player_id_of(u) == player_id:
				out.append(u)
		return out

	if PlayerManager == null or not PlayerManager.has_method("get_player_by_id"):
		return out
	var player = PlayerManager.get_player_by_id(player_id)
	if player == null or not ("owned_units" in player):
		return out
	for u in player.owned_units:
		if u != null and is_instance_valid(u):
			out.append(u)
	return out


static func _player_id_of_player(player) -> int:
	if player == null:
		return -1
	if not ("player_id" in player):
		return -1
	return int(player.player_id)


static func _player_id_of(unit) -> int:
	if unit == null or not is_instance_valid(unit):
		return -1
	if unit.has_method("get_owner_player"):
		var owner_player = unit.get_owner_player()
		if owner_player != null and ("player_id" in owner_player):
			return int(owner_player.player_id)
	var t = unit.get("team")
	if t != null:
		return int(t)
	return -1


static func _character_id_of(unit) -> String:
	if unit == null or not is_instance_valid(unit):
		return ""
	var cr = unit.get("character_resource")
	if cr != null:
		var cid = cr.get("character_id")
		if cid != null:
			return String(cid)
	var direct = unit.get("character_id")
	if direct != null:
		return String(direct)
	return ""


## The cell [param unit] stands on, via the shared live board. (-1,-1) with no board.
func _cell_of(unit) -> Vector2i:
	if _board_override != null:
		return _board_override.cell_of(unit)
	if CombatServices == null:
		return Vector2i(-1, -1)
	var board = CombatServices.board()
	if board == null or not board.has_method("cell_of"):
		return Vector2i(-1, -1)
	return board.cell_of(unit)


func set_board_override(board) -> void:
	_board_override = board


func set_spawner_override(spawner) -> void:
	_spawner_override = spawner


## The battle's [SpawnManager], reached through [code]GameWorldManager[/code]'s group -- the
## one node that owns it (it is recreated per battle, so it can never be cached here).
func _spawn_manager():
	if _spawner_override != null:
		return _spawner_override
	var tree: SceneTree = _tree()
	if tree == null:
		return null
	var gwm = tree.get_first_node_in_group("game_world_manager")
	if gwm == null or not is_instance_valid(gwm) or not gwm.has_method("get_spawn_manager"):
		return null
	return gwm.get_spawn_manager()


## The [MapResource] this battle loaded, via the battle's own [GameWorldManager] group (the
## same route [ObjectiveBanner] takes). Null outside a battle.
func _live_map():
	var tree: SceneTree = _tree()
	if tree == null:
		return null
	var gwm = tree.get_first_node_in_group("game_world_manager")
	if gwm == null or not is_instance_valid(gwm):
		return null
	var loader = gwm.get("map_loader")
	if loader == null or not is_instance_valid(loader):
		return null
	if loader.has_method("get_current_map"):
		return loader.get_current_map()
	return loader.get("current_map")


## This node's [SceneTree], or null while it is not in one. [code]get_tree()[/code] ERRORS on a
## node with no tree, and this singleton is deliberately outside it for one frame after
## installation (see [method _install]), so every tree lookup goes through here.
func _tree() -> SceneTree:
	if not is_inside_tree():
		return null
	return get_tree()


## Coerce an authored waypoint list into [Vector2i]s. A .tres map hands back Vector2i already;
## a JSON map hands back plain Arrays of floats (CONQUEST.md rule 3), so both are accepted.
static func _to_cells(raw) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for item in raw as Array:
		var cell: Vector2i = _to_cell(item)
		if cell.x >= 0 and cell.y >= 0:
			out.append(cell)
	return out


static func _to_cell(item) -> Vector2i:
	if item is Vector2i:
		return item
	if item is Vector2:
		return Vector2i(item)
	if item is Array and (item as Array).size() >= 2:
		return Vector2i(int((item as Array)[0]), int((item as Array)[1]))
	if item is Dictionary:
		var d: Dictionary = item as Dictionary
		if d.has("x") and d.has("y"):
			return Vector2i(int(d["x"]), int(d["y"]))
	return Vector2i(-1, -1)
