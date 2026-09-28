extends Node
class_name DuelBattle

## THE DUEL ENGINE: one 1v1 battle on a [DuelBoard], with no presentation. [DuelStage] wraps
## it with a stage, camera and HUD; tests and dev_scripts/duel_smoke.gd run it headless.
##
## It is the tactical engine on a two-station board (docs/design/DUEL_BATTLE.md §3): real
## character-backed [Unit]s, the live [CombatServices] board, a [DuelTurnSystem], and every
## action applied as a COMMAND through [CommandApplier] -- the one deterministic apply path
## the replays and network play use. Nothing here computes damage (rule 9).
##
## DETERMINISM (DECISIONS.md): every duel starts from FRESH entropy unless its request pins
## a seed; the seed actually used is recorded on the result. Each command is stamped with
## its seq and its own per-action seed ([method MatchRng.seed_for]) before it is applied, so
## the recorded command list replays byte-for-byte ([method replay_commands]). The duel-only
## draws -- the speed tie-break, EASY AI, the befriend roll -- use separate salts and never
## shift a combat roll.
##
## Flow: [method setup] -> [method start] -> per turn either [method submit_slot] (human),
## [method play_ai_turn] (AI) or [method pass_turn] (a stunned / controlled unit), until
## [signal finished]. [method run_to_end] drives AI-only duels synchronously.

## A new combatant's turn opened (after its turn-start ticks). [param unit] may need to pass.
signal turn_opened(unit)
## A command was applied: { cmd, result, actor, slot, move, hp: [a, b] }.
signal action_resolved(record: Dictionary)
signal finished(result: DuelResult)

const GRID: Grid = preload("res://board/Grid.tres")
const UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")

## Domain salts for the duel-only streams (never shared with a combat roll).
const SALT_TIE := 0x44756554  # "DueT"
const SALT_AI := 0x44756541   # "DueA"
const SALT_BEFRIEND := 0x44756542  # "DueB"

var request: DuelRequest = null
var rules: DuelRuleset = null
var board: DuelBoard = null
var turn_system: DuelTurnSystem = null
var applier: CommandApplier = null
var match_rng: MatchRng = null
## [side 0 player, side 1 foe].
var players: Array[Player] = []
## The active (fielded) combatant per side; null once KO'd and freed.
var active: Array = [null, null]
## Compiled private characters per side (for the HUD: notes, struggle).
var characters: Array = [null, null]
var map_root: Node3D = null
var result: DuelResult = null
var is_over: bool = false

var _started: bool = false
var _seq: int = 0
var _use_turn_manager: bool = false
var _owns_map: bool = false
var _replaying: bool = false
var _subdued: Array[bool] = [false, false]
var _ko: Array[bool] = [false, false]
var _final_hp: Array[int] = [0, 0]


# --- Setup ---------------------------------------------------------------------------

## Build the duel from [param p_request]: compile both leads, spawn them on their stations
## under [param p_map_root] (a "Map" node with Player1 / Player2 children is created when
## null), install the [DuelBoard] and the turn system. [param use_turn_manager] also makes the
## duel's turn system the ACTIVE one in [TurnSystemManager] (the live stage does, so the HUD
## widgets that follow the active system work). Returns { success, reason } (rule 1).
func setup(p_request: DuelRequest, p_map_root: Node3D = null, use_turn_manager: bool = false) -> Dictionary:
	if p_request == null:
		return _fail("no_request")
	var check := p_request.validate()
	if not bool(check["success"]):
		return check
	request = p_request
	rules = request.load_ruleset()
	_use_turn_manager = use_turn_manager

	match_rng = MatchRng.new()
	if request.seed != 0:
		match_rng.begin_from_seed(request.seed)
	else:
		match_rng.begin_solo(MatchRng.fresh_entropy())

	CombatServices.clear()
	CombatServices.match_rng = null
	CombatServices.weather.configure({"mode": "fixed", "weather": String(request.weather_id)},
		match_rng.seed_for(NetSessionNode.LOCAL_WEATHER_SEQ))

	map_root = p_map_root
	if map_root == null:
		map_root = Node3D.new()
		map_root.name = "Map"
		add_child(map_root)
		_owns_map = true
	for side_name in ["Player1", "Player2"]:
		if map_root.get_node_or_null(side_name) == null:
			var n := Node3D.new()
			n.name = side_name
			map_root.add_child(n)

	players.clear()
	players.append(Player.new(0, "Challenger"))
	players.append(Player.new(1, "Foe"))
	players[0].is_ai = request.player_is_ai
	players[1].is_ai = request.foe_is_ai

	board = DuelBoard.new(GRID, Callable(self, "active_units"), rules.station_gap)
	var tile := TileCatalog.find_by_id(request.resolved_station_tile_id())
	for side in 2:
		CombatServices.register_tile(board.station(side), tile)

	for side in 2:
		var party: Array[DuelCombatant] = request.player_party if side == 0 else request.foe_party
		var spawned := _spawn_lead(side, party[0])
		if not bool(spawned["success"]):
			return spawned

	CombatServices.install_board(board)
	NetUnitIds.assign(board, true)
	for side in 2:
		var u = active[side]
		if u != null:
			u.set_facing(Vector2i(1, 0) if side == 0 else Vector2i(-1, 0), 0.0)

	turn_system = DuelTurnSystem.new()
	turn_system.name = "DuelTurnSystem"
	turn_system.tie_seed = MatchRng._mix([SALT_TIE, match_rng.match_seed])
	turn_system.timer_seconds = rules.turn_timer_seconds
	add_child(turn_system)
	for p in players:
		turn_system.register_player(p)
	turn_system.turn_started.connect(_on_turn_started)

	applier = CommandApplier.new(null, match_rng,
		func(): return board, func(): return turn_system)

	result = DuelResult.new()
	result.seed = match_rng.match_seed
	result.encounter_id = request.encounter_id
	result.stats = [_blank_stats(), _blank_stats()]
	if GameEvents != null and not GameEvents.damage_dealt.is_connected(_on_damage_dealt):
		GameEvents.damage_dealt.connect(_on_damage_dealt)
	ModeTuning.register(self)
	return {"success": true, "reason": ""}


## Open the first turn (ON_BATTLE_START then the fastest unit's turn-start ticks).
func start() -> void:
	if _started or turn_system == null:
		return
	_started = true
	# Rolls made before the first command (battle-start abilities, the opening tick) draw
	# from the setup stream, exactly like a solo tactical battle.
	NetGameRules.install_setup_rng(match_rng.seed_for(NetSessionNode.LOCAL_SETUP_SEQ))
	if _use_turn_manager and TurnSystemManager != null:
		# A previous battle's players / systems must not leak into this one: the manager
		# registers every PlayerManager player into the system it activates.
		if PlayerManager != null:
			PlayerManager.reset_for_new_game()
		TurnSystemManager.reset_for_new_game()
		TurnSystemManager.switch_to_turn_system(turn_system)
	else:
		turn_system.is_active = true
		turn_system.start_turn_system()


func _spawn_lead(side: int, combatant: DuelCombatant) -> Dictionary:
	var roster := CharacterLibrary.get_character(combatant.character_id)
	if roster == null:
		return _fail("unknown_character")
	var compiled := DuelMoveCompiler.compile(roster, rules)
	if not bool(compiled["success"]):
		return compiled
	var dc: DuelCharacter = compiled["character"]
	DuelScaling.apply(dc, combatant.strength)
	characters[side] = dc

	var unit: Unit = UNIT_SCENE.instantiate()
	# Before add_child: Unit._ready builds its stats / moveset / status / ability
	# components from the character it already holds.
	unit.character_resource = dc
	unit.name = String(dc.character_id).capitalize().replace(" ", "")
	unit.position = board.station_world(side)
	map_root.get_node(["Player1", "Player2"][side]).add_child(unit)
	players[side].add_unit(unit)
	unit.set_meta(&"duel_side", side)
	if combatant.current_hp >= 0 and combatant.current_hp < unit.max_health:
		unit.set_stat("health", maxi(1, combatant.current_hp))
	if not combatant.item_ids.is_empty():
		_apply_items(unit, combatant.item_ids)
	active[side] = unit
	unit.unit_died.connect(_on_unit_died)
	return {"success": true, "reason": ""}


## Equipment loadout, exactly as a tactical battle applies it (no board needed).
func _apply_items(unit: Unit, item_ids: Array[String]) -> void:
	var items: Array[ItemResource] = []
	for id in item_ids:
		var item := ItemLibrary.get_item(id)
		if item != null:
			items.append(item)
	if not items.is_empty():
		ItemSystem.apply_loadout_items(unit, items)


# --- Queries ---------------------------------------------------------------------------

## The ACTIVE combatants (the board's units provider): alive, valid, fielded.
func active_units() -> Array:
	var out: Array = []
	for u in active:
		if u != null and is_instance_valid(u) and u.is_alive():
			out.append(u)
	return out


func unit_of(side: int):
	var u = active[side] if side >= 0 and side < 2 else null
	return u if u != null and is_instance_valid(u) else null


func side_of(unit) -> int:
	for side in 2:
		if active[side] == unit:
			return side
	return -1


func foe_of(unit):
	var side := side_of(unit)
	return unit_of(1 - side) if side >= 0 else null


## The unit whose turn it is, or null (not started / over).
func current_actor():
	if is_over or turn_system == null or not turn_system.is_active:
		return null
	var u = turn_system.get_current_acting_unit()
	return u if u != null and is_instance_valid(u) and u.is_alive() else null


func is_ai_unit(unit) -> bool:
	var side := side_of(unit)
	return side >= 0 and players[side].is_ai


## True while [param unit]'s turn is being skipped (stunned) or taken over (controlled):
## the duel spends it with a WAIT.
func must_pass(unit) -> bool:
	if unit == null or turn_system == null:
		return false
	return turn_system.is_turn_skipped(unit) or turn_system.is_turn_forced_control(unit)


## Slots [param unit] may pick now: its ready moves, or the struggle when none is ready.
func legal_slots(unit) -> Array[int]:
	var slots := DuelBrain.ready_slots(unit)
	if slots.is_empty():
		var s := DuelBrain.struggle_slot(unit)
		if s != DuelBrain.NO_SLOT:
			slots.append(s)
	return slots


func round_number() -> int:
	if is_over and result != null:
		return result.rounds
	return turn_system.round_number if turn_system != null else 0


## The seeded stream for side [param side]'s EASY brain at the next command.
func ai_rng(side: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = MatchRng._mix([SALT_AI, match_rng.match_seed, _seq + 1, side])
	return r


## The befriend roll's stream: the battle's seed under its own salt (DECISIONS.md).
func befriend_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = MatchRng._mix([SALT_BEFRIEND, match_rng.match_seed])
	return r


## Difficulty for the AI on [param side] (the request's, else the rules's).
func difficulty_for(side: int) -> int:
	var d: int = request.player_ai_difficulty if side == 0 else request.ai_difficulty
	return d if d >= 0 else rules.ai_difficulty


## ModeTuning provider hooks (rule 11: the engine reads duel knobs through ModeTuning).
func ruleset() -> Resource:
	return rules


func rounds_elapsed() -> int:
	return round_number()


func is_armed() -> bool:
	return _started and not is_over


# --- Actions ---------------------------------------------------------------------------

## The human picks [param slot] for the acting unit. Returns the applied record, or
## { ok: false, reason } for an illegal pick (rule 1).
func submit_slot(slot: int) -> Dictionary:
	var actor = current_actor()
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if must_pass(actor):
		return {"ok": false, "reason": "must_pass"}
	if not (slot in legal_slots(actor)):
		return {"ok": false, "reason": "slot_unavailable"}
	var aim := DuelBrain.aim_for(actor, foe_of(actor), board, slot)
	return apply_command(NetProtocol.use_move(NetUnitIds.id_of(actor), slot, aim))


## Let the brain act for the current (AI) unit.
func play_ai_turn() -> Dictionary:
	var actor = current_actor()
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if must_pass(actor):
		return pass_turn()
	return apply_decision(actor, decide_for(actor))


## What the brain would do for [param actor] right now (pure: the stage asks first so it
## can play an ultimate's cut-in BEFORE the command resolves). Its EASY stream is keyed to
## the next command's seq, so asking early changes nothing.
func decide_for(actor) -> Dictionary:
	var side := side_of(actor)
	return DuelBrain.decide(actor, foe_of(actor), board, rules, difficulty_for(side), ai_rng(side))


## Apply a [method decide_for] decision as the acting unit's command.
func apply_decision(actor, decision: Dictionary) -> Dictionary:
	var slot: int = int(decision.get("slot", DuelBrain.NO_SLOT))
	if actor == null or actor != current_actor():
		return {"ok": false, "reason": "no_actor"}
	if slot == DuelBrain.NO_SLOT:
		return pass_turn()
	return apply_command(NetProtocol.use_move(NetUnitIds.id_of(actor), slot, decision["aim_cell"]))


## Spend the acting unit's turn (stunned, controlled, or nothing to do).
func pass_turn() -> Dictionary:
	var actor = current_actor()
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	return apply_command(NetProtocol.wait(NetUnitIds.id_of(actor)))


## Apply [param cmd] through THE apply path. Unstamped commands get the next seq and their
## own per-action seed (the replay then needs no stream at all). Returns the record.
func apply_command(cmd: Dictionary) -> Dictionary:
	if is_over:
		return {"ok": false, "reason": "duel_over"}
	var c := cmd.duplicate(true)
	if int(c.get(NetProtocol.KEY_SEQ, 0)) <= 0:
		_seq += 1
		c[NetProtocol.KEY_SEQ] = _seq
	else:
		_seq = maxi(_seq, int(c[NetProtocol.KEY_SEQ]))
	if int(c.get(NetProtocol.KEY_RNG, 0)) == 0:
		var s: int = match_rng.seed_for(int(c[NetProtocol.KEY_SEQ]))
		c[NetProtocol.KEY_RNG] = s if s != 0 else 1
	var actor = applier.find_unit(String((c.get(NetProtocol.KEY_DATA, {}) as Dictionary).get(NetProtocol.K_UNIT, "")))
	var side := side_of(actor)
	c[NetProtocol.KEY_ACTOR] = side
	var slot: int = int((c[NetProtocol.KEY_DATA] as Dictionary).get(NetProtocol.K_SLOT, -1))
	var move: MoveResource = actor.get_move(slot) if actor != null and slot >= 0 else null

	var res := applier.apply_command(c, board, {"turn_system": turn_system})
	result.commands.append(c)
	if bool(res.get("ok", false)) and move != null and side >= 0:
		var used: Dictionary = result.stats[side]["moves_used"]
		used[String(move.move_id)] = int(used.get(String(move.move_id), 0)) + 1
	_note_subdue(res, side)

	# The state hash is taken HERE, before any end-of-duel teardown, so a live run and its
	# replay hash exactly the same moment.
	var record := {"ok": bool(res.get("ok", false)), "cmd": c, "result": res, "actor": actor,
		"side": side, "slot": slot, "move": move, "hp": _hp_row(),
		"hash": applier.hash_match_state(board)}
	result.hp_timeline.append({"seq": int(c[NetProtocol.KEY_SEQ]), "actor": side,
		"hp": _hp_row(), "statuses": _status_row()})
	result.turns = result.commands.size()

	if _check_end():
		action_resolved.emit(record)
		_finish()
		return record
	# A kept move that granted CANTO leaves the turn open (there is nowhere to walk):
	# close it with a recorded WAIT so the queue advances.
	if not _replaying and actor != null and is_instance_valid(actor) and actor == turn_system.get_current_acting_unit() \
			and turn_system.is_turn_in_progress and actor.has_method("has_canto") and actor.has_canto():
		action_resolved.emit(record)
		return apply_command(NetProtocol.wait(NetUnitIds.id_of(actor)))
	action_resolved.emit(record)
	return record


## Drive the duel synchronously while only AI (or passing) units act. Stops at a human
## turn, at the end, or after [param max_actions]. Returns the result (null while running).
func run_to_end(max_actions: int = 400) -> DuelResult:
	if not _started:
		start()
	var n := 0
	while not is_over and n < max_actions:
		var actor = current_actor()
		if actor == null:
			break
		if must_pass(actor):
			pass_turn()
		elif is_ai_unit(actor):
			play_ai_turn()
		else:
			break
		n += 1
	return result if is_over else null


## Forfeit / quit: the duel ends as ABORTED (no winner, no befriend).
func forfeit() -> void:
	if is_over:
		return
	result.outcome = DuelResult.OUTCOME_ABORTED
	result.winner_side = -1
	_finish(true)


## Re-apply a recorded [param commands] list (each already stamped) on this freshly set-up
## duel. Returns the per-command state hashes (CommandApplier.hash_match_state).
func replay_commands(commands: Array) -> Array[int]:
	var hashes: Array[int] = []
	if not _started:
		start()
	_replaying = true  # the recording already holds every follow-up command
	for cmd in commands:
		if is_over:
			break
		var rec := apply_command(cmd)
		hashes.append(int(rec.get("hash", 0)))
	return hashes


# --- End -------------------------------------------------------------------------------

func _check_end() -> bool:
	if is_over:
		return true
	for side in 2:
		if _ko[side]:
			return true
		var u = unit_of(side)
		if u == null or not u.is_alive():
			_ko[side] = true
			return true
	return false


func _finish(aborted: bool = false) -> void:
	if is_over:
		return
	is_over = true
	for side in 2:
		var u = unit_of(side)
		if u != null and u.is_alive():
			_final_hp[side] = int(u.get_hp())
	result.rounds = turn_system.round_number if turn_system != null else 0
	if not aborted:
		var a_alive := not _ko[0]
		var b_alive := not _ko[1]
		result.winner_side = 0 if (a_alive and not b_alive) else (1 if (b_alive and not a_alive) else -1)
		# Both falling on the same blow (a reprisal trade) is not a win for the challenger.
		result.outcome = DuelResult.OUTCOME_VICTORY if result.winner_side == 0 else DuelResult.OUTCOME_DEFEAT
		for side in 2:
			if _ko[1 - side]:
				result.stats[side]["kos"] = 1
	_build_party_after()
	if result.winner_side == 0:
		for c in request.foe_party.slice(0, 1):
			result.defeated.append(String(c.character_id))
		if request.is_wild():
			var foe_id := String(request.foe_party[0].character_id)
			var roll := rules.roll_join(befriend_rng(), _subdued[1])
			result.befriend_offer = {
				"character_id": foe_id,
				"offered": bool(roll["offered"]),
				"accepted": false,
				"chance": float(roll["chance"]),
				"roll": float(roll["roll"]),
				"subdued": bool(roll["subdued"]),
			}
	if turn_system != null:
		if _use_turn_manager and TurnSystemManager != null and TurnSystemManager.get_active_turn_system() == turn_system:
			TurnSystemManager.deactivate_turn_system()
		elif turn_system.is_active:
			turn_system.end_turn_system()
	ModeTuning.unregister(self)
	finished.emit(result)


func _build_party_after() -> void:
	result.party_after.clear()
	for i in range(request.player_party.size()):
		var c: DuelCombatant = request.player_party[i]
		var fielded := i == 0
		var hp: int = c.current_hp
		var wounded := false
		if fielded:
			wounded = _ko[0]
			hp = 0 if wounded else _final_hp[0]
		result.party_after.append({"member_id": c.member_id, "character_id": String(c.character_id),
			"current_hp": hp, "wounded": wounded})


# --- Bookkeeping -----------------------------------------------------------------------

func _on_turn_started(_player) -> void:
	var u = turn_system.get_current_acting_unit() if turn_system != null else null
	if u != null and is_instance_valid(u) and not is_over:
		turn_opened.emit(u)


func _on_unit_died(unit) -> void:
	var side := side_of(unit)
	if side < 0:
		return
	_ko[side] = true
	_final_hp[side] = 0


func _on_damage_dealt(attacker, defender, amount) -> void:
	var a := side_of(attacker)
	var d := side_of(defender)
	if d < 0:
		return
	result.stats[d]["damage_taken"] = int(result.stats[d]["damage_taken"]) + int(amount)
	if a >= 0 and a != d:
		result.stats[a]["damage_dealt"] = int(result.stats[a]["damage_dealt"]) + int(amount)


func _note_subdue(res: Dictionary, side: int) -> void:
	for e in res.get("events", []):
		if e is Dictionary and bool(e.get("subdued", false)):
			var target_side := side_of(e.get("target"))
			if target_side >= 0 and target_side != side:
				_subdued[target_side] = true


## [side A hp, side B hp] (0 once KO'd).
func _hp_row() -> Array:
	var row: Array = []
	for side in 2:
		var u = unit_of(side)
		row.append(int(u.get_hp()) if u != null and u.is_alive() else 0)
	return row


func _status_row() -> Array:
	var row: Array = []
	for side in 2:
		var u = unit_of(side)
		row.append(NetGameRules.statuses_sorted(u) if u != null and u.is_alive() else [])
	return row


static func _blank_stats() -> Dictionary:
	return {"damage_dealt": 0, "damage_taken": 0, "kos": 0, "moves_used": {}}


static func _fail(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}


## Tear the duel's global state down (the live board, the installed RNG, the mode
## registration). Safe to call twice; the owner calls it when leaving the duel.
func teardown() -> void:
	if GameEvents != null and GameEvents.damage_dealt.is_connected(_on_damage_dealt):
		GameEvents.damage_dealt.disconnect(_on_damage_dealt)
	ModeTuning.unregister(self)
	if _use_turn_manager and TurnSystemManager != null and TurnSystemManager.get_active_turn_system() == turn_system:
		TurnSystemManager.deactivate_turn_system()
	elif turn_system != null and turn_system.is_active:
		turn_system.end_turn_system()
	if CombatServices.board() == board:
		CombatServices.clear()
	CombatServices.match_rng = null


func _exit_tree() -> void:
	teardown()
