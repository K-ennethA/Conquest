extends Node
class_name DuelBattle

## THE DUEL ENGINE: one battle between two TEAMS on a [DuelBoard], with no presentation.
## [DuelStage] wraps it with a stage, camera and HUD; tests and dev_scripts/duel_smoke.gd run it
## headless.
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
## [method submit_switch] (human: the Party action, costs the turn), [method use_item] (human: a
## battle consumable, costs the turn), [method play_ai_turn] (AI) or [method pass_turn] (a
## stunned / controlled unit); after a faint the owner's [method choose_replacement] /
## [method play_ai_replacement]; until [signal finished].
##
## PARTY DUELS (the request's [DuelFormat]: Singles 1v1, Trio 3v3, Full 6v6, custom). Each side
## fields ONE combatant (the lead) on its station; the rest of its TEAM waits on the bench as
## real [Unit]s that are hidden, invisible to the board and unregistered from the turn system
## (so nothing ticks for them: their cooldowns and lasting statuses are frozen).
##   * SWITCH (the Party action, [constant NetProtocol.Action.SWITCH]) resolves in the switching
##     combatant's own speed slot and SPENDS its turn: its turn ends normally, it leaves the
##     field (what survives: [member DuelRuleset.persist_on_switch]) and the incoming member
##     does not act again this round.
##   * KO REPLACEMENT: a fainted combatant's owner picks who comes in -- a recorded SWITCH that
##     is free and immediate (before any other turn opens; the newcomer waits for the next
##     round). With [member DuelRuleset.ko_replacement] off the next healthy member in team
##     order enters automatically (no choice, so no command).
##   * A side with nobody left standing loses; both at once (a reprisal trade) is no win for A.
## A benched member first entering gets its ON_BATTLE_START moment then ("the battle began for
## it when it took the field"), exactly once.
##
## ITEMS (DECISIONS.md #28): the player side carries [member DuelRequest.items] (the story bag's
## battle consumables). Using one is the recorded USE_ITEM command through the same apply path
## as a move -- deterministic (no roll) and replayed byte-for-byte; what was used comes back as
## [member DuelResult.items_used] for the story to take from the bag. The AI never uses items.
## [method run_to_end] drives AI-only duels synchronously.

## A new combatant's turn opened (after its turn-start ticks). [param unit] may need to pass.
signal turn_opened(unit)
## A command was applied: { cmd, result, actor, slot, move, hp: [a, b], switch }.
signal action_resolved(record: Dictionary)
signal finished(result: DuelResult)
## PARTY DUELS: side [param side]'s fielded combatant fainted and its owner must pick who comes
## in ([method choose_replacement] / [method play_ai_replacement]) before anything else happens.
signal replacement_needed(side: int)
## A team member took the field (a switch or a KO replacement). [param previous] is the unit that
## left by a voluntary switch (null for a replacement). The stage presents it; the HUD rebinds.
signal combatant_entered(side: int, unit, previous)

const GRID: Grid = preload("res://board/Grid.tres")
const UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")

## Domain salts for the duel-only streams (never shared with a combat roll).
const SALT_TIE := 0x44756554  # "DueT"
const SALT_AI := 0x44756541   # "DueA"
const SALT_BEFRIEND := 0x44756542  # "DueB"
const SALT_FLEE := 0x44756546  # "DueF"

## Scene parents: the fielded leads under Map/Player1|2 (the TurnSystemManager scan registers
## them), the bench under Map/Bench1|2 (never scanned -- a benched member takes no turns).
const FIELD_NODES: Array[String] = ["Player1", "Player2"]
const BENCH_NODES: Array[String] = ["Bench1", "Bench2"]

var request: DuelRequest = null
## The rules this duel plays by: the request's ruleset with its [DuelFormat] applied, a private
## copy (rule 7) -- what ModeTuning serves while the duel is armed.
var rules: DuelRuleset = null
var board: DuelBoard = null
var turn_system: DuelTurnSystem = null
var applier: CommandApplier = null
var match_rng: MatchRng = null
## [side 0 player, side 1 foe].
var players: Array[Player] = []
## The active (fielded) combatant per side; null while a side has nobody on its station.
var active: Array = [null, null]
## The fielded combatant's compiled private character per side (for the HUD: notes, struggle).
var characters: Array = [null, null]
## PARTY: per side, one record per TEAM member, lead first:
##   {side, index, combatant, unit, character, fainted, fielded, kos, turns}
## (fielded = took the field at some point; turns = turns opened since it last came in).
var teams: Array = [[], []]
var map_root: Node3D = null
var result: DuelResult = null
var is_over: bool = false

var _started: bool = false
var _seq: int = 0
var _use_turn_manager: bool = false
var _owns_map: bool = false
var _replaying: bool = false
var _subdued: Array[bool] = [false, false]
## A side with nobody left standing.
var _out: Array[bool] = [false, false]
## A side whose owner must pick a KO replacement.
var _pending: Array[bool] = [false, false]
var _newly_pending: Array[int] = []
## [side, index] of every member that fainted, in order.
var _fainted_order: Array = []
## unit instance id -> the stat-modifier ids it was built with (equipment): a switch-out clears
## only what the battle added.
var _base_modifiers: Dictionary = {}
var _flee_attempts: int = 0
## The player side's battle items left ({item_id: count}), from the request.
var _items_left: Dictionary = {}


# --- Setup ---------------------------------------------------------------------------

## Build the duel from [param p_request]: compile every team member, spawn the leads on their
## stations and the bench off the field under [param p_map_root] (a "Map" node is created when
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
	rules = request.battle_rules()
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
	for side_name in FIELD_NODES + BENCH_NODES:
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
	board.switch_handler = Callable(self, "_apply_switch")
	var tile := TileCatalog.find_by_id(request.resolved_station_tile_id())
	for side in 2:
		CombatServices.register_tile(board.station(side), tile)

	# The turn system exists (players registered, owning nothing yet) BEFORE the units: a lead
	# is registered with it explicitly, a bench member never is (it joins when it takes the field).
	turn_system = DuelTurnSystem.new()
	turn_system.name = "DuelTurnSystem"
	turn_system.tie_seed = MatchRng._mix([SALT_TIE, match_rng.match_seed])
	turn_system.timer_seconds = rules.turn_timer_seconds
	# A story wild duel started by contact: the ambushing side opens round 1 (-1 = speed order).
	turn_system.first_side = request.opening_side()
	add_child(turn_system)
	for p in players:
		turn_system.register_player(p)
	turn_system.turn_started.connect(_on_turn_started)

	teams = [[], []]
	for side in 2:
		var team := request.team_of(side)
		for i in range(team.size()):
			var spawned := _spawn_member(side, i, team[i])
			if not bool(spawned["success"]):
				return spawned

	CombatServices.install_board(board)
	NetUnitIds.assign(board, true)

	applier = CommandApplier.new(null, match_rng,
		func(): return board, func(): return turn_system)

	result = DuelResult.new()
	result.seed = match_rng.match_seed
	result.encounter_id = request.encounter_id
	result.stats = [_blank_stats(), _blank_stats()]
	_items_left = request.items.duplicate()
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
	# The opening tick can already knock someone out (a battle-start burst, a carried poison).
	_newly_pending.clear()
	_settle_state()
	if _out[0] or _out[1]:
		_finish()
		return
	for s in _newly_pending:
		replacement_needed.emit(s)


## Build one team member: compile its private duel character, scale it, spawn its unit on the
## side's station (the lead fielded; a bench member hidden, parked, unowned by the turn system).
func _spawn_member(side: int, index: int, combatant: DuelCombatant) -> Dictionary:
	var roster := CharacterLibrary.get_character(combatant.character_id)
	if roster == null:
		return _fail("unknown_character")
	# A human's story weapon override (validated on import); the roster entry is never touched.
	if not combatant.weapon_id.is_empty():
		roster = roster.with_weapon(WeaponLibrary.get_weapon(combatant.weapon_id))
	var compiled := DuelMoveCompiler.compile(roster, rules)
	if not bool(compiled["success"]):
		return compiled
	var dc: DuelCharacter = compiled["character"]
	# STORY LEVEL first (the one stat-at-level function, on this private copy -- rule 7), then the
	# opaque strength multiplier on top. A level of 0 (every open-mode duel) changes nothing.
	Progression.apply_level(dc, combatant.level)
	DuelScaling.apply(dc, rules.clamp_strength(combatant.strength))
	var lead := index == 0

	var unit: Unit = UNIT_SCENE.instantiate()
	# Before add_child: Unit._ready builds its stats / moveset / status / ability
	# components from the character it already holds.
	unit.character_resource = dc
	unit.name = String(dc.character_id).capitalize().replace(" ", "") + ("" if lead else str(index))
	unit.position = board.station_world(side)
	map_root.get_node(FIELD_NODES[side] if lead else BENCH_NODES[side]).add_child(unit)
	unit.set_meta(&"duel_side", side)
	unit.set_meta(&"duel_member", index)
	if combatant.level > 0:
		unit.set_meta(StoryBattleBridge.LEVEL_META, combatant.level)
	# Stable ids from the TEAM, not the board: "<side>:<member>" (a lead is "<side>:0", exactly
	# what NetUnitIds.assign would have named it), identical on every peer and replay.
	unit.set_meta(NetUnitIds.META, "%d:%d" % [side, index])
	players[side].add_unit(unit)
	if lead:
		turn_system.register_unit(unit)
	if combatant.current_hp >= 0 and combatant.current_hp < unit.max_health:
		unit.set_stat("health", maxi(1, combatant.current_hp))
	if rules.allow_held_items and not combatant.item_ids.is_empty():
		_apply_items(unit, combatant.item_ids)
	_base_modifiers[unit.get_instance_id()] = unit.unit_stats.modifier_ids() if unit.unit_stats != null else []
	unit.set_facing(Vector2i(1, 0) if side == 0 else Vector2i(-1, 0), 0.0)
	var rec := {"side": side, "index": index, "combatant": combatant, "unit": unit, "character": dc,
		"fainted": false, "fielded": lead, "kos": 0, "turns": 0}
	teams[side].append(rec)
	if lead:
		active[side] = unit
		characters[side] = dc
	else:
		unit.visible = false
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


## The side a team member belongs to (fielded, benched or fainted), or -1.
func side_of(unit) -> int:
	if unit == null or not is_instance_valid(unit) or not (unit is Object) or not unit.has_meta(&"duel_side"):
		return -1
	return int(unit.get_meta(&"duel_side"))


func foe_of(unit):
	var side := side_of(unit)
	return unit_of(1 - side) if side >= 0 else null


## The unit whose turn it is, or null (not started / over / a KO replacement is pending).
func current_actor():
	if is_over or turn_system == null or not turn_system.is_active or has_pending_replacement():
		return null
	if not turn_system.is_turn_in_progress:
		return null
	var u = turn_system.get_current_acting_unit()
	return u if u != null and is_instance_valid(u) and u.is_alive() else null


func is_ai_unit(unit) -> bool:
	var side := side_of(unit)
	return side >= 0 and players[side].is_ai


func is_ai_side(side: int) -> bool:
	return side >= 0 and side < players.size() and players[side].is_ai


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


# --- Party queries ---------------------------------------------------------------------

## Side [param side]'s team records (lead first; see [member teams]).
func team(side: int) -> Array:
	return teams[side] if side >= 0 and side < 2 else []


func team_size(side: int) -> int:
	return team(side).size()


## The fielded member's index on [param side], or -1 while nobody is on the station.
func active_index(side: int) -> int:
	var u = unit_of(side)
	if u == null:
		return -1
	return int(u.get_meta(&"duel_member", -1))


## The team record whose unit carries net id [param id] ({} when none).
func member_by_id(id: String) -> Dictionary:
	for side in 2:
		for rec in teams[side]:
			if NetUnitIds.id_of(rec["unit"]) == id or (not is_instance_valid(rec["unit"]) and id == "%d:%d" % [side, int(rec["index"])]):
				return rec
	return {}


## The net id of side [param side]'s member [param index] ("<side>:<index>").
static func member_id(side: int, index: int) -> String:
	return "%d:%d" % [side, index]


## Indices of [param side]'s members that could come in now: healthy and not on the station.
func usable_bench(side: int) -> Array[int]:
	var out: Array[int] = []
	for rec in team(side):
		var u = rec["unit"]
		if bool(rec["fainted"]) or u == null or not is_instance_valid(u) or u == active[side]:
			continue
		out.append(int(rec["index"]))
	return out


## Healthy benched members of [param side] as {index, unit} rows (what the brain weighs).
func bench_units(side: int) -> Array:
	var out: Array = []
	for i in usable_bench(side):
		out.append({"index": i, "unit": teams[side][i]["unit"]})
	return out


## Sides whose owner must pick a KO replacement now (side 0 first).
func pending_replacements() -> Array[int]:
	var out: Array[int] = []
	for side in 2:
		if _pending[side]:
			out.append(side)
	return out


func has_pending_replacement() -> bool:
	return _pending[0] or _pending[1]


func is_pending(side: int) -> bool:
	return side >= 0 and side < 2 and _pending[side]


## True when the side has nobody left standing.
func is_side_out(side: int) -> bool:
	return side >= 0 and side < 2 and _out[side]


## May [param unit] (the acting combatant) switch right now?
func can_switch(unit) -> bool:
	var side := side_of(unit)
	return side >= 0 and switch_problem(side, -1, false, true) == ""


## Why side [param side]'s member [param index] may not come in now, or "" when it may. A
## [param replacement] answers for a pending KO replacement, otherwise for a voluntary switch on
## the side's own turn. [param any_member] skips the member checks (can the side switch at all?).
## The reasons are the NetProtocol INTENT_* wire strings, so the online rules return them as-is.
func switch_problem(side: int, index: int, replacement: bool, any_member: bool = false) -> String:
	if is_over:
		return NetProtocol.INTENT_DUEL_OVER
	if side < 0 or side > 1:
		return NetProtocol.INTENT_UNKNOWN_ACTOR
	if replacement:
		if not _pending[side]:
			return NetProtocol.INTENT_ILLEGAL_SWITCH
	else:
		if has_pending_replacement():
			return NetProtocol.INTENT_MUST_PICK
		if rules == null or not rules.allow_switch:
			return NetProtocol.INTENT_NO_SWITCHING
		var actor = current_actor()
		if actor == null:
			return NetProtocol.INTENT_NO_ACTIVE_TURN
		if side_of(actor) != side:
			return NetProtocol.INTENT_NOT_YOUR_TURN
		if must_pass(actor):
			return NetProtocol.INTENT_MUST_PASS
	var bench := usable_bench(side)
	if any_member:
		return "" if not bench.is_empty() else NetProtocol.INTENT_ILLEGAL_SWITCH
	if not (index in bench):
		return NetProtocol.INTENT_ILLEGAL_SWITCH
	return ""


## The rows a team strip / party picker shows for [param side]: [{index, name, character_id,
## element, hp, max_hp, fainted, active, fielded}] (lead first).
func team_view(side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec in team(side):
		var u = rec["unit"]
		var valid: bool = u != null and is_instance_valid(u)
		var ch: CharacterResource = rec["character"]
		var fainted := bool(rec["fainted"])
		out.append({
			"index": int(rec["index"]),
			"name": u.get_display_name() if valid else (ch.display_name if ch != null else String(rec["combatant"].character_id)),
			"character_id": String(rec["combatant"].character_id),
			"element": ch.element if ch != null else &"",
			"hp": 0 if fainted or not valid else int(u.get_hp()),
			"max_hp": int(u.max_health) if valid else (ch.base_health if ch != null else 1),
			"fainted": fainted,
			"active": valid and u == active[side],
			"fielded": bool(rec["fielded"]),
			"unit": u if valid else null,
		})
	return out


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


## The acting side switches its fielded combatant for bench member [param index] (the Party
## action): the recorded SWITCH command, which spends the turn. {ok: false, reason} (nothing
## spent) when switching is off, it is not the side's turn, or that member cannot come in.
func submit_switch(index: int) -> Dictionary:
	var actor = current_actor()
	if actor == null:
		return {"ok": false, "reason": NetProtocol.INTENT_NO_ACTIVE_TURN}
	var side := side_of(actor)
	var why := switch_problem(side, index, false)
	if why != "":
		return {"ok": false, "reason": why}
	return apply_command(NetProtocol.switch_to(member_id(side, index)))


## Side [param side]'s owner picks who replaces its fainted combatant (a free, recorded SWITCH).
func choose_replacement(side: int, index: int) -> Dictionary:
	var why := switch_problem(side, index, true)
	if why != "":
		return {"ok": false, "reason": why}
	return apply_command(NetProtocol.switch_to(member_id(side, index)))


## The brain's replacement pick for [param side] (a team index; -1 when none can come in).
func decide_replacement(side: int) -> int:
	return DuelBrain.pick_replacement(unit_of(1 - side), board, rules, difficulty_for(side), bench_units(side))


## Let the brain pick side [param side]'s KO replacement.
func play_ai_replacement(side: int) -> Dictionary:
	return choose_replacement(side, decide_replacement(side))


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
## the next command's seq, so asking early changes nothing. A SWITCH decision carries
## [code]switch[/code] (the bench index) and slot NO_SLOT.
func decide_for(actor) -> Dictionary:
	var side := side_of(actor)
	var diff := difficulty_for(side)
	var d := DuelBrain.decide(actor, foe_of(actor), board, rules, diff, ai_rng(side))
	if rules.allow_switch and not must_pass(actor):
		var rec: Dictionary = teams[side][int(actor.get_meta(&"duel_member", 0))]
		var idx := DuelBrain.consider_switch(actor, foe_of(actor), board, rules, diff, bench_units(side),
			d, int(rec.get("turns", 0)))
		if idx >= 0:
			d = {"slot": DuelBrain.NO_SLOT, "switch": idx, "aim_cell": d.get("aim_cell", Vector3i.ZERO),
				"reason": "switch", "score": float(d.get("score", 0.0)), "scores": d.get("scores", {})}
	return d


## Apply a [method decide_for] decision as the acting unit's command.
func apply_decision(actor, decision: Dictionary) -> Dictionary:
	if actor == null or actor != current_actor():
		return {"ok": false, "reason": "no_actor"}
	if decision.has("switch"):
		return submit_switch(int(decision["switch"]))
	var slot: int = int(decision.get("slot", DuelBrain.NO_SLOT))
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
	var t: int = int(c.get(NetProtocol.KEY_TYPE, -1))
	var data: Dictionary = c.get(NetProtocol.KEY_DATA, {}) if c.get(NetProtocol.KEY_DATA, {}) is Dictionary else {}
	var actor = null
	var side := -1
	if t == NetProtocol.Action.SWITCH:
		# The incoming member is benched (not on the board): the side is the team's, and the
		# record's actor is whoever leaves the station (null for a KO replacement).
		var m := member_by_id(String(data.get(NetProtocol.K_UNIT, "")))
		side = int(m.get("side", -1))
		actor = unit_of(side) if side >= 0 else null
	else:
		actor = applier.find_unit(String(data.get(NetProtocol.K_UNIT, "")))
		side = side_of(actor)
	c[NetProtocol.KEY_ACTOR] = side
	var slot: int = int(data.get(NetProtocol.K_SLOT, -1))
	var move: MoveResource = actor.get_move(slot) if actor != null and slot >= 0 else null

	var res := applier.apply_command(c, board, {"turn_system": turn_system})
	result.commands.append(c)
	if bool(res.get("ok", false)) and move != null and side >= 0:
		var used: Dictionary = result.stats[side]["moves_used"]
		used[String(move.move_id)] = int(used.get(String(move.move_id), 0)) + 1
	if bool(res.get("ok", false)) and t == NetProtocol.Action.USE_ITEM and side == 0:
		# The item leaves the side's bag here -- live and in a replay alike.
		var item_id: String = String(data.get(NetProtocol.K_ITEM, ""))
		_items_left[item_id] = maxi(0, int(_items_left.get(item_id, 0)) - 1)
		result.items_used[item_id] = int(result.items_used.get(item_id, 0)) + 1
	_note_subdue(res, side)

	# Faints -> KO replacements / the end; otherwise the queue moves on. Deterministic and
	# identical live, online and in a replay (the recorded picks re-apply as commands).
	_newly_pending.clear()
	_settle_state()
	var switch_event: Dictionary = {}
	for e in res.get("events", []):
		if e is Dictionary and String(e.get("effect", "")) == "switch":
			switch_event = e

	# The state hash is taken HERE, before any end-of-duel teardown, so a live run and its
	# replay hash exactly the same moment.
	var record := {"ok": bool(res.get("ok", false)), "cmd": c, "result": res, "actor": actor,
		"side": side, "slot": slot, "move": move, "hp": _hp_row(), "switch": switch_event,
		"hash": state_hash()}
	result.hp_timeline.append({"seq": int(c[NetProtocol.KEY_SEQ]), "actor": side,
		"hp": _hp_row(), "statuses": _status_row(), "team_hp": _team_hp_rows()})
	result.turns = result.commands.size()

	if _out[0] or _out[1]:
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
	var pending_now := _newly_pending.duplicate()
	for s in pending_now:
		replacement_needed.emit(s)
	return record


## Drive the duel synchronously while only AI (or passing) units act. Stops at a human
## turn (or a human's KO replacement pick), at the end, or after [param max_actions]. Returns
## the result (null while running).
func run_to_end(max_actions: int = 400) -> DuelResult:
	if not _started:
		start()
	var n := 0
	while not is_over and n < max_actions:
		var pending := pending_replacements()
		if not pending.is_empty():
			if not is_ai_side(pending[0]):
				break
			play_ai_replacement(pending[0])
			n += 1
			continue
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


## Can the acting human run right now? The encounter must allow it
## ([method DuelRequest.can_flee]: wild duels) AND the ruleset ([member DuelRuleset.allow_flee]).
func can_flee() -> bool:
	if is_over or request == null or rules == null:
		return false
	return request.can_flee() and rules.allow_flee


## The player tries to RUN (docs/design/DUEL_BATTLE.md §4.3). The chance is the ruleset's
## [method DuelRuleset.flee_chance] (speed difference + attempts so far), rolled from the duel's
## seeded stream under its own salt (never a combat roll, never randf()). Success ends the duel
## as FLED (no winner, no befriend, HP carried); failure spends the turn as a recorded WAIT.
## Returns {ok, reason, fled, chance, roll}.
func attempt_flee() -> Dictionary:
	var actor = current_actor()
	if actor == null:
		return {"ok": false, "reason": "no_actor", "fled": false}
	if side_of(actor) != 0 or is_ai_unit(actor):
		return {"ok": false, "reason": "not_player_turn", "fled": false}
	if not can_flee():
		return {"ok": false, "reason": "cannot_flee", "fled": false}
	var foe = foe_of(actor)
	var chance: float = rules.flee_chance(int(actor.get_stat("speed")),
		int(foe.get_stat("speed")) if foe != null else 0, _flee_attempts)
	var rng := RandomNumberGenerator.new()
	rng.seed = MatchRng._mix([SALT_FLEE, match_rng.match_seed, _flee_attempts])
	var roll: float = -1.0
	var fled: bool = chance >= 1.0
	if not fled:
		roll = rng.randf()
		fled = roll < chance
	_flee_attempts += 1
	if fled:
		result.outcome = DuelResult.OUTCOME_FLED
		result.winner_side = -1
		_finish(true)
		return {"ok": true, "reason": "", "fled": true, "chance": chance, "roll": roll}
	pass_turn()
	return {"ok": true, "reason": "", "fled": false, "chance": chance, "roll": roll}


# --- Items ------------------------------------------------------------------------------

## Battle items the player side still holds ({item_id: count}, a copy).
func items_left() -> Dictionary:
	return _items_left.duplicate()


## May the acting human use an item right now? The ruleset must allow items
## ([member DuelRuleset.allow_items]) and the side must hold at least one.
func can_use_items() -> bool:
	if is_over or rules == null or not rules.allow_items:
		return false
	for id in _items_left:
		if int(_items_left[id]) > 0:
			return true
	return false


## The item picker rows for [param actor] (sorted by name): [{item_id, item, count, ok, reason}]
## -- ok false (with the [ConsumableEffect] reason) when using it now would be wasted. The target
## is the actor itself (the fielded combatant is the only ally on the field).
func item_options(actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _items_left:
		var n: int = int(_items_left[id])
		var item: ItemResource = ItemLibrary.get_item(String(id))
		if n <= 0 or item == null or item.consumable == null:
			continue
		var check: Dictionary = item.consumable.check_unit(actor)
		out.append({"item_id": String(id), "item": item, "count": n, "ok": bool(check["ok"]),
			"reason": String(check["reason"])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["item"] as ItemResource).display_name.naturalnocasecmp_to((b["item"] as ItemResource).display_name) < 0)
	return out


## The human uses [param item_id] on its own combatant: the USE_ITEM command (costs the turn).
## Returns the applied record, or {ok: false, reason} (nothing spent) when it is not the
## player's turn, items are off, none is left, or it would be wasted ("full_hp", ...).
func use_item(item_id: String) -> Dictionary:
	var actor = current_actor()
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if side_of(actor) != 0 or is_ai_unit(actor):
		return {"ok": false, "reason": "not_player_turn"}
	if must_pass(actor):
		return {"ok": false, "reason": "must_pass"}
	if rules == null or not rules.allow_items:
		return {"ok": false, "reason": "items_disabled"}
	if int(_items_left.get(item_id, 0)) <= 0:
		return {"ok": false, "reason": "no_item"}
	var item: ItemResource = ItemLibrary.get_item(item_id)
	if item == null or item.consumable == null:
		return {"ok": false, "reason": "not_consumable"}
	var check: Dictionary = item.consumable.check_unit(actor)
	if not bool(check["ok"]):
		return {"ok": false, "reason": String(check["reason"])}
	var id: String = NetUnitIds.id_of(actor)
	return apply_command(NetProtocol.use_item(id, item_id, id))


## VERSUS (online / hot-seat): [param side] walks away -- a forfeit or a dropped connection.
## The OTHER side wins, recorded like a KO win from side A's point of view (VICTORY when side
## A remains, DEFEAT when side B does; no befriend). Idempotent; ignored once decided.
func concede(side: int) -> void:
	if is_over or result == null or side < 0 or side > 1:
		return
	result.winner_side = 1 - side
	result.outcome = DuelResult.OUTCOME_VICTORY if result.winner_side == 0 else DuelResult.OUTCOME_DEFEAT
	_finish(true)


## Forfeit / quit: the duel ends as ABORTED (no winner, no befriend).
func forfeit() -> void:
	if is_over:
		return
	result.outcome = DuelResult.OUTCOME_ABORTED
	result.winner_side = -1
	_finish(true)


## Re-apply a recorded [param commands] list (each already stamped) on this freshly set-up
## duel. Returns the per-command state hashes ([method state_hash]).
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


# --- Switching (apply side) --------------------------------------------------------------

## THE apply half of a SWITCH ([DuelBoard.apply_switch] <- [method NetGameRules._apply]): a
## pending KO replacement brings the member in (free); otherwise the acting combatant spends
## its turn leaving the station and the member comes in. Never validates beyond null-safety
## (the local caller / the host / every client already did), so peers cannot diverge on it.
func _apply_switch(data: Dictionary, _ts) -> Dictionary:
	var rec := member_by_id(String(data.get(NetProtocol.K_UNIT, "")))
	if rec.is_empty():
		return {"ok": false, "reason": NetProtocol.INTENT_UNKNOWN_UNIT}
	var side: int = int(rec["side"])
	var index: int = int(rec["index"])
	var incoming = rec["unit"]
	if bool(rec["fainted"]) or incoming == null or not is_instance_valid(incoming) or incoming == active[side]:
		return {"ok": false, "reason": NetProtocol.INTENT_ILLEGAL_SWITCH}
	var replacement: bool = _pending[side]
	var outgoing = unit_of(side)
	if replacement:
		_pending[side] = false
		_bring_in(side, index)
	else:
		if outgoing == null:
			return {"ok": false, "reason": NetProtocol.INTENT_ILLEGAL_SWITCH}
		turn_system.retire_for_switch(outgoing)
		_bench_active(side)
		_bring_in(side, index)
		turn_system.advance_after_switch()
	combatant_entered.emit(side, incoming, null if replacement else outgoing)
	return {"ok": true, "events": [{"effect": "switch", "side": side, "index": index,
		"replacement": replacement, "unit": incoming, "unit_id": NetUnitIds.id_of(incoming),
		"from": outgoing, "from_id": NetUnitIds.id_of(outgoing) if outgoing != null else ""}]}


## The fielded combatant of [param side] leaves the station: what the battle gave or took is
## cleared (everything but [member DuelRuleset.persist_on_switch] statuses, the equipment's own
## modifiers, HP and cooldowns), it hides, and the board no longer sees it.
func _bench_active(side: int) -> void:
	var u = unit_of(side)
	if u == null:
		return
	_clear_battle_state(u)
	u.visible = false
	active[side] = null


func _clear_battle_state(u) -> void:
	var sc = u.get_status_controller() if u.has_method("get_status_controller") else null
	if sc != null and sc.has_method("get_active"):
		var ids: Array[StringName] = []
		for cond in sc.get_active():
			if cond == null or rules.persists_on_switch(cond.id) or cond.id in ids:
				continue
			# A pending burst leaves with its caster (it fizzles; it never erupts on the way out).
			if "hazard" in cond:
				cond.set("hazard", null)
			ids.append(cond.id)
		for id in ids:
			sc.remove_status(id, board)
	var stats = u.unit_stats if "unit_stats" in u else null
	if stats != null and stats.has_method("modifier_ids"):
		var keep: Array = _base_modifiers.get(u.get_instance_id(), [])
		for mid in stats.modifier_ids():
			if not (mid in keep):
				stats.remove_stat_modifier(mid)
	if "shield_hp" in u and int(u.shield_hp) > 0:
		u.shield_hp = 0
		u.shield_changed.emit(0)
	if u.has_method("set_forced_control"):
		u.set_forced_control(false)


## Member [param index] of [param side] takes the station: shown, board-visible, adopted by the
## turn system (marked as having acted this round), its first battle-start moment spent.
func _bring_in(side: int, index: int) -> void:
	var rec: Dictionary = teams[side][index]
	var u = rec["unit"]
	u.position = board.station_world(side)
	u.visible = true
	active[side] = u
	characters[side] = rec["character"]
	rec["fielded"] = true
	rec["turns"] = 0
	u.set_facing(Vector2i(1, 0) if side == 0 else Vector2i(-1, 0), 0.0)
	if u.has_method("reset_turn_actions"):
		u.reset_turn_actions()
	turn_system.adopt_incoming(u)
	var abilities = u.get_ability_system() if u.has_method("get_ability_system") else null
	if _started and abilities != null and abilities.has_method("dispatch_battle_start"):
		abilities.dispatch_battle_start(board)


## Resolve faints: a side whose station emptied either picks a replacement (pending), gets the
## next member automatically ([member DuelRuleset.ko_replacement] off) or is OUT. When nobody is
## waiting on a pick, the queue resumes (which may open a turn whose ticks faint someone else --
## hence the loop).
func _settle_state() -> void:
	if turn_system == null:
		return
	for _i in range(16):
		for side in 2:
			if unit_of(side) != null and unit_of(side).is_alive():
				continue
			active[side] = null
			if _out[side] or _pending[side]:
				continue
			var bench := usable_bench(side)
			if bench.is_empty():
				_out[side] = true
			elif rules.ko_replacement:
				_pending[side] = true
				_newly_pending.append(side)
			else:
				_bring_in(side, bench[0])
				combatant_entered.emit(side, teams[side][bench[0]]["unit"], null)
		if _out[0] or _out[1] or has_pending_replacement():
			return
		if not turn_system.is_active or turn_system.is_turn_in_progress:
			return
		turn_system.resume_if_idle()
		if turn_system.is_turn_in_progress and unit_of(0) != null and unit_of(1) != null:
			return


# --- End -------------------------------------------------------------------------------

func _finish(aborted: bool = false) -> void:
	if is_over:
		return
	is_over = true
	result.rounds = turn_system.round_number if turn_system != null else 0
	if not aborted:
		var a_alive := not _out[0]
		var b_alive := not _out[1]
		result.winner_side = 0 if (a_alive and not b_alive) else (1 if (b_alive and not a_alive) else -1)
		# Both falling on the same blow (a reprisal trade) is not a win for the challenger.
		result.outcome = DuelResult.OUTCOME_VICTORY if result.winner_side == 0 else DuelResult.OUTCOME_DEFEAT
	for side in 2:
		var kos := 0
		for rec in teams[1 - side]:
			if bool(rec["fainted"]):
				kos += 1
		result.stats[side]["kos"] = kos
	_build_party_after()
	for entry in _fainted_order:
		if int(entry[0]) == 1:
			result.defeated.append(String(teams[1][int(entry[1])]["combatant"].character_id))
	if result.winner_side == 0 and request.can_befriend():
		var foe_id := String(request.foe_party[0].character_id)
		# STORY: the species' catch rate multiplies the chance (DECISIONS.md #78); open modes roll 1.0.
		var catch_mult: float = 1.0
		if request.origin == DuelRequest.ORIGIN_STORY:
			catch_mult = Progression.catch_rate_of(CharacterLibrary.get_character(StringName(foe_id)))
		var roll := rules.roll_join(befriend_rng(), _subdued[1], catch_mult)
		result.befriend_offer = {
			"character_id": foe_id,
			# The level it was met at: a befriended creature joins at it (PROGRESSION.md §1).
			"level": request.foe_party[0].level,
			# A story-critical recruit is never missable: a win always offers.
			"offered": bool(roll["offered"]) or request.is_story_critical(),
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


## The player side's party after the duel ([member DuelResult.party_after]): every TEAM member
## that took the field "fought" (story Growth) and, when it fainted, is "wounded" -- a KO'd bench
## member switched in counts exactly like the lead (Classic permadeath marks each one). Members
## that never took the field -- the bench nobody needed, or party members past the format's team
## size -- keep their HP.
func _build_party_after() -> void:
	result.party_after.clear()
	for i in range(request.player_party.size()):
		var c: DuelCombatant = request.player_party[i]
		var hp: int = c.current_hp
		var wounded := false
		var fought := false
		var kos := 0
		if i < teams[0].size():
			var rec: Dictionary = teams[0][i]
			var u = rec["unit"]
			fought = bool(rec["fielded"])
			wounded = bool(rec["fainted"])
			kos = int(rec["kos"])
			if wounded:
				hp = 0
			elif fought and u != null and is_instance_valid(u) and u.is_alive():
				hp = int(u.get_hp())
		# `fought` / `kos` feed story Growth (StoryGrowth).
		result.party_after.append({"member_id": c.member_id, "character_id": String(c.character_id),
			"current_hp": hp, "wounded": wounded, "fought": fought, "kos": kos})


# --- Bookkeeping -----------------------------------------------------------------------

func _on_turn_started(_player) -> void:
	var u = turn_system.get_current_acting_unit() if turn_system != null else null
	if u != null and is_instance_valid(u) and not is_over:
		var side := side_of(u)
		var idx := int(u.get_meta(&"duel_member", -1))
		if side >= 0 and idx >= 0 and idx < teams[side].size():
			teams[side][idx]["turns"] = int(teams[side][idx]["turns"]) + 1
		turn_opened.emit(u)


func _on_unit_died(unit) -> void:
	var side := side_of(unit)
	if side < 0:
		return
	var idx := int(unit.get_meta(&"duel_member", -1))
	if idx < 0 or idx >= teams[side].size():
		return
	var rec: Dictionary = teams[side][idx]
	if bool(rec["fainted"]):
		return
	rec["fainted"] = true
	_fainted_order.append([side, idx])
	if active[side] == unit:
		active[side] = null
	# The KO is credited to the other side's fielded combatant (story Growth).
	var killer_idx := active_index(1 - side)
	if killer_idx >= 0:
		teams[1 - side][killer_idx]["kos"] = int(teams[1 - side][killer_idx]["kos"]) + 1


func _on_damage_dealt(attacker, defender, amount) -> void:
	var a := side_of(attacker)
	var d := side_of(defender)
	if d < 0 or result == null:
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


## [side A hp, side B hp] of the fielded combatants (0 while a station is empty).
func _hp_row() -> Array:
	var row: Array = []
	for side in 2:
		var u = unit_of(side)
		row.append(int(u.get_hp()) if u != null and u.is_alive() else 0)
	return row


## Every team member's HP per side ([[a0, a1..], [b0, b1..]]; 0 once fainted).
func _team_hp_rows() -> Array:
	var rows: Array = []
	for side in 2:
		var row: Array = []
		for rec in teams[side]:
			var u = rec["unit"]
			row.append(0 if bool(rec["fainted"]) or u == null or not is_instance_valid(u) else int(u.get_hp()))
		rows.append(row)
	return rows


func _status_row() -> Array:
	var row: Array = []
	for side in 2:
		var u = unit_of(side)
		row.append(NetGameRules.statuses_sorted(u) if u != null and u.is_alive() else [])
	return row


## The parties' comparable state: per member its side, index, fainted / fielded / on-station
## flags, HP, statuses and cooldowns, plus the pending replacements. Folded into
## [method state_hash] and the online digest, so a benched unit's state is checked too.
func party_digest() -> Array:
	var rows: Array = []
	for side in 2:
		for rec in teams[side]:
			var u = rec["unit"]
			var live: bool = u != null and is_instance_valid(u) and not bool(rec["fainted"])
			rows.append([side, int(rec["index"]), bool(rec["fainted"]), bool(rec["fielded"]),
				live and u == active[side], int(u.get_hp()) if live else 0,
				NetGameRules.statuses_sorted(u) if live else [],
				NetGameRules.cooldowns_sorted(u) if live else []])
	return [rows, _pending[0], _pending[1], _out[0], _out[1]]


## The replay / desync checksum: the board digest (fielded units, turn, weather) plus the parties.
func state_hash() -> int:
	return hash([applier.hash_match_state(board), party_digest()])


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
