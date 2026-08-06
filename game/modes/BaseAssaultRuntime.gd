extends Node
class_name BaseAssaultRuntime

## The tiny runtime a BASE-ASSAULT map ([DestroyBase]) needs on top of its win
## condition. Owned by the mode layer, armed and disarmed from
## [method WinConditionLibrary.build_rules], and completely INERT on every other map.
##
## It does exactly two jobs a pure, stateless [WinCondition] cannot:
##
## 1. NEUTRAL FACTION REGISTRATION. A base-assault map fields guardian camps on
##    player slot 2. [MapLoader] happily builds a "Player3" container for them, but
##    single-player setup only ever registers TWO players
##    ([code]PlayerManager.setup_default_players[/code]), so
##    [code]PlayerManager.assign_units_by_parent[/code] -- which loops
##    [code]range(players.size())[/code] -- never adopts that container. An unowned
##    unit is worse than useless: [code]BoardAdapter.are_enemies[/code] returns false
##    the moment EITHER side has no owner, so an unowned guardian can neither attack
##    nor BE attacked, and it never takes a turn. The Arena solves this by calling
##    [code]PlayerManager.ensure_neutral_player()[/code] from its round builder before
##    players are assigned (see [ArenaRoundBuilder]); a map-driven mode has no such
##    builder, so this node does the same thing off
##    [code]PlayerManager.player_registered[/code] -- the one signal that fires
##    between "the two combatants exist" and "units get assigned".
##
## 2. NEUTRAL BOUNTY. Killing a guardian is meant to be worth taking a risk for, so
##    the killer's WHOLE SIDE gets a small permanent attack buff. (A per-UNIT reward
##    already exists -- [member Unit.kill_reward], a StatusCondition handed to whoever
##    lands the killing blow, used by the Arena camps. That is deliberately not reused
##    here: this bounty is a TEAM buff, and it has to survive the killer's own death,
##    which a status on one unit does not.) The running total per team is remembered so
##    units that arrive LATER -- and on this map they arrive endlessly -- spawn with the
##    bounty already applied instead of the buff evaporating with the units that earned it.
##
##    A MODE MAY MAKE THAT REWARD TEMPORARY. The permanent bump is the right shape for one
##    push and one fight; a mode that re-fights the same jungle for twenty rounds compounds it
##    into a lead nothing can answer. So a mode declares [constant CAMP_BUFF_KNOB] on its own
##    ruleset and the reward becomes a TIMED status of that many turns instead -- same event,
##    same side-wide scope, different vehicle. The knob is read through [ModeTuning], so this
##    node still knows nothing about which mode is running and a map that declares nothing
##    pays the permanent bounty exactly as it always did (CONQUEST.md rule 11).
##
## LIFETIME. A process-wide singleton (like the mode controllers that are autoloads),
## parented to the scene-tree root so it outlives every scene change. It is created
## lazily the first time a base-assault map compiles its rules and simply goes quiet
## (see [method set_armed]) when any other map loads, so no other mode's behaviour
## changes. Arming also RESETS the per-battle state, which is what makes a second
## battle in the same app run start from zero.

## Node name in the scene-tree root (also how a stale instance is recognised).
const NODE_NAME := "BaseAssaultRuntime"

## Stat the guardian bounty raises, and by how much per guardian felled.
const BOUNTY_STAT := "attack"
const BOUNTY_AMOUNT := 1

## The knob a MODE declares to convert its camp reward from the permanent bounty above into a
## TIMED buff (see [method camp_buff_turns]). Named here, read through [ModeTuning]: this node
## never references a mode's controller or holds a mode's constant (CONQUEST.md rule 11).
const CAMP_BUFF_KNOB: StringName = &"camp_buff_turns"

## The player slot the neutral faction always occupies. Mirrors
## [code]PlayerManager.NEUTRAL_PLAYER_INDEX[/code] the same way
## [code]ArenaRoundBuilder.NEUTRAL_PLAYER_ID[/code] does, so this file does not depend
## on reaching a constant through an autoload instance.
const NEUTRAL_SLOT: int = 2

## The single live instance, or null before the first base-assault map.
static var _instance: BaseAssaultRuntime = null

## While false every handler returns immediately -- the node exists but does nothing.
var _armed: bool = false

## Latched once the neutral faction has been registered for THIS battle, so a repeat
## player_registered (or a second call in the same setup pass) cannot register it twice.
var _neutral_ensured: bool = false

## team id -> total bounty attack granted to that side so far this battle.
var _team_bonus: Dictionary = {}

## defender instance id -> attacker instance id, tracked off GameEvents.damage_dealt.
## GameEvents.unit_eliminated is emitted with a NULL eliminator (see Unit._on_unit_died),
## so the killer has to be reconstructed the same way [member Unit._last_damager] does.
var _last_damager: Dictionary = {}

## Optional board seam. When null the live board is read off CombatServices; tests inject a
## lightweight fake so the bounty can be paid headless. Mirrors
## [code]SiegeController._board_override[/code].
var _board_override = null


# --- Arming (called from WinConditionLibrary) --------------------------------

## Bring the runtime in line with a freshly compiled [param rules] set: install +
## arm it when the rules contain a [DestroyBase] objective, disarm it otherwise.
## Returns the live instance, or null when there is nothing to do and none exists.
static func sync(rules: GameModeRules) -> BaseAssaultRuntime:
	var wants: bool = _rules_want_runtime(rules)

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


## True when this battle is a PUSH map -- one that fields a neutral guardian faction on slot 2
## in front of endlessly reinforcing lines.
##
## That is BASE-ASSAULT ([DestroyBase]) and SIEGE alike. The two modes end differently -- one
## by flattening a structure, one by holding its cell ([CaptureBase]) -- but the two jobs this
## node does are about the BOARD, not the objective: a third faction has to be registered or
## its guardians are unowned scenery, and felling one has to be worth the risk. Keying this to
## DestroyBase alone was an accident of base-assault having shipped first; a Siege map with
## jungle camps needs exactly the same two things, and got neither.
##
## A Siege map is recognised the same way [SiegeController] recognises one -- its compiled
## objective OR its authored lanes + base cells -- so a Siege map that names "Destroy Enemy
## Base" and one that names "Capture Enemy Base" both arm this, and nothing else changes.
static func _rules_want_runtime(rules: GameModeRules) -> bool:
	if rules != null:
		for c in rules.win_conditions:
			if c is DestroyBase or c is CaptureBase:
				return true
		for c in rules.lose_conditions:
			if c is DestroyBase or c is CaptureBase:
				return true
	return SiegeController.map_declares_siege()


## Create the singleton and wire it to the event buses.
##
## The signal hook-ups happen BEFORE the node is in the tree on purpose: rules are
## compiled from [code]GameWorldManager._on_map_loaded[/code], which runs inside the
## battle scene's own [code]_ready[/code] cascade, and adding a child to the root
## right then can trip Godot's "parent node is busy" guard. Connections do not need
## the node to be in the tree, so the parenting is deferred purely for lifetime
## management while the handlers are live immediately -- which matters, because the
## player registration this node listens for happens in the very same frame.
static func _install() -> BaseAssaultRuntime:
	var node := BaseAssaultRuntime.new()
	node.name = NODE_NAME
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	node._connect_bus()

	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		(loop as SceneTree).root.call_deferred("add_child", node)
	return node


## Arm (or silence) the runtime. Arming RESETS every per-battle latch, so each map
## load starts a clean battle; disarming leaves the node connected but inert.
func set_armed(value: bool) -> void:
	_armed = value
	if value:
		_neutral_ensured = false
		_team_bonus.clear()
		_last_damager.clear()


func is_armed() -> bool:
	return _armed


## Accumulated bounty attack granted to [param team] this battle (0 when none).
## Public for tests / HUD.
func team_bonus(team: int) -> int:
	return int(_team_bonus.get(team, 0))


## Full TURNS a camp kill's buff lasts under the ACTIVE mode, or 0 for "no timer".
##
## 0 is the answer on a base-assault map, in a skirmish, and anywhere else no mode declares
## the knob -- and 0 means the PERMANENT bounty this node has always paid, unchanged. A mode
## that declares [constant CAMP_BUFF_KNOB] (Siege does: it respawns both squads and re-fights
## the same jungle for twenty rounds, where a permanent per-kill bump compounds into a lead
## nothing can answer) gets a timed buff of that many turns instead. Public so a HUD and the
## tests can ask which reward is live.
func camp_buff_turns() -> int:
	return ModeTuning.camp_buff_turns()


## Inject a board (tests). Null restores the live one off CombatServices.
func set_board_override(board) -> void:
	_board_override = board


# --- Bus wiring --------------------------------------------------------------

func _connect_bus() -> void:
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null:
		_safe_connect(GameEvents, &"damage_dealt", _on_damage_dealt)
		_safe_connect(GameEvents, &"unit_eliminated", _on_unit_eliminated)
		_safe_connect(GameEvents, &"unit_spawned", _on_unit_spawned)
	if PlayerManager != null:
		_safe_connect(PlayerManager, &"player_registered", _on_player_registered)


func _safe_connect(bus, signal_name: StringName, handler: Callable) -> void:
	if bus == null or not bus.has_signal(signal_name):
		return
	if not bus.is_connected(signal_name, handler):
		bus.connect(signal_name, handler)


# --- 1. Neutral faction registration -----------------------------------------

## Register the neutral faction the instant the SECOND combatant lands, which is the
## only window between "both combatants exist" and
## [code]PlayerManager.assign_units_by_parent[/code] adopting the map's containers.
##
## Gated on player_id == 1 specifically: reacting to player 0 instead would make
## [code]ensure_neutral_player[/code] fill the missing slot 1 itself, and the
## registration still to come would then land at slot 3. The neutral it registers has
## id 2, so it never re-enters this branch.
func _on_player_registered(player) -> void:
	if not _armed or _neutral_ensured or player == null:
		return
	if not ("player_id" in player) or int(player.player_id) != 1:
		return
	if PlayerManager == null or not PlayerManager.has_method("ensure_neutral_player"):
		return
	# Only when the loaded map actually fields neutrals -- an empty extra faction would
	# still be handed turns it can do nothing with.
	if not _map_fields_neutrals():
		return
	_neutral_ensured = true
	PlayerManager.ensure_neutral_player()


## True when the live board carries units in the NEUTRAL player's container.
## [MapLoader] names containers "Player<slot+1>" under the scene's "Map" node, and the
## map is fully loaded before players are set up, so the container's child count is a
## direct read of "did this map author any neutrals".
func _map_fields_neutrals() -> bool:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return false
	var scene = (loop as SceneTree).current_scene
	if scene == null:
		return false
	var container = scene.get_node_or_null("Map/Player%d" % (NEUTRAL_SLOT + 1))
	return container != null and container.get_child_count() > 0


# --- 2. Neutral bounty --------------------------------------------------------

## Remember who last hit each unit, so a guardian's death can credit a killer.
func _on_damage_dealt(attacker, defender, _amount) -> void:
	if not _armed:
		return
	if attacker == null or defender == null or attacker == defender:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return
	_last_damager[defender.get_instance_id()] = attacker.get_instance_id()


## A neutral guardian fell: grant its killer's whole side a permanent attack bump.
## Everything here is best-effort -- an unattributable kill (a hazard, a tile, a unit
## that died before this one) simply grants nothing rather than erroring.
func _on_unit_eliminated(unit, eliminator = null) -> void:
	if not _armed or unit == null:
		return

	var neutral: bool = _is_neutral_unit(unit)
	var killer = eliminator
	if killer == null:
		killer = _resolve_last_damager(unit)
	if is_instance_valid(unit):
		_last_damager.erase(unit.get_instance_id())

	if not neutral:
		return
	if killer == null or not is_instance_valid(killer):
		return

	var team: int = _team_of_unit(killer)
	if team < 0:
		return

	# THE TIMED FORK. Same event, same SCOPE (the killer's whole side, so the reward survives
	# the killer's own death), two vehicles -- and which one is live is the active mode's data,
	# never a branch on which mode is running.
	var turns: int = camp_buff_turns()
	if turns > 0:
		_grant_timed_buff(team, turns)
		return

	_team_bonus[team] = team_bonus(team) + BOUNTY_AMOUNT
	_grant_to_living(team, BOUNTY_AMOUNT)


## Carry the accumulated bounty onto a unit that arrives AFTER it was earned (this
## map's endless waves). Deferred because the spawn signal fires from inside
## [code]MapLoader._create_unit_from_spawn[/code], BEFORE the spawner assigns the
## unit an owner -- and the owner is what says which side's bonus applies.
func _on_unit_spawned(unit, _runtime = false) -> void:
	if not _armed or unit == null:
		return
	call_deferred("_apply_carried_bonus", unit)


func _apply_carried_bonus(unit) -> void:
	if not _armed or unit == null or not is_instance_valid(unit):
		return
	var team: int = _team_of_unit(unit)
	if team < 0:
		return
	var carried: int = team_bonus(team)
	if carried <= 0:
		return
	_add_modifier(unit, carried)


## Apply [param amount] to every unit currently owned by [param team].
func _grant_to_living(team: int, amount: int) -> void:
	for u in _side_units(team):
		_add_modifier(u, amount)


## Hand every living unit of [param team] the TIMED camp buff, for [param turns] turns.
##
## Nothing is accumulated into [member _team_bonus]: that ledger exists so a unit arriving
## LATER can be given a bounty earned before it spawned, which is exactly the property a timed
## buff must NOT have -- a reinforcement three rounds after the kill would otherwise walk out
## with a fresh full-length copy of a buff that has already run out. So under the timed reward
## the buff is granted once, to who is on the board, and it times out on its own.
##
## Iteration order is the roster's, and a re-grant REFRESHES ([ModeTuning.grant_camp_buff]),
## so a second camp kill resets one timer rather than deepening anything.
func _grant_timed_buff(team: int, turns: int) -> void:
	for u in _side_units(team):
		ModeTuning.grant_camp_buff(u, turns)


## Every living unit belonging to [param team].
##
## Read off the BOARD first -- the same source the win conditions are scored against, and the
## seam a test injects -- and only through [PlayerManager] when there is no board with an
## `all_units` hook. Mirrors [code]SiegeController._units_of[/code].
func _side_units(team: int) -> Array:
	var out: Array = []
	var board = _board_override
	if board == null and CombatServices != null:
		board = CombatServices.board()
	if board != null and board.has_method("all_units"):
		for u in board.all_units():
			if u != null and is_instance_valid(u) and _team_of_unit(u) == team:
				out.append(u)
		return out

	if PlayerManager == null or not PlayerManager.has_method("get_player_by_id"):
		return out
	var player = PlayerManager.get_player_by_id(team)
	if player == null or not ("owned_units" in player):
		return out
	for u in player.owned_units:
		if u != null and is_instance_valid(u):
			out.append(u)
	return out


## Indefinite (-1 duration) stat modifier: nothing expires it, so the bounty lasts the
## rest of the battle. Duck-typed so a mock without the API is simply skipped.
func _add_modifier(unit, amount: int) -> void:
	if unit == null or not unit.has_method("add_stat_modifier"):
		return
	unit.add_stat_modifier(BOUNTY_STAT, amount, -1)


# --- Shared helpers -----------------------------------------------------------

func _resolve_last_damager(unit):
	if unit == null or not is_instance_valid(unit):
		return null
	var attacker_id: int = int(_last_damager.get(unit.get_instance_id(), 0))
	# 0 = never recorded; the validity check covers a killer freed between the hit and
	# this death (instance_from_id on a stale id is an error, not a null).
	if attacker_id == 0 or not is_instance_id_valid(attacker_id):
		return null
	return instance_from_id(attacker_id)


## Owning player slot of [param unit], or -1 when it has none.
static func _team_of_unit(unit) -> int:
	if unit == null:
		return -1
	if unit.has_method("get_team"):
		return int(unit.get_team())
	var t = unit.get("team")
	if t != null:
		return int(t)
	return -1


## True when [param unit] belongs to the neutral faction.
static func _is_neutral_unit(unit) -> bool:
	if unit == null:
		return false
	var direct = unit.get("is_neutral")
	if direct != null:
		return bool(direct)
	if unit.has_method("get_owner_player"):
		var owner_player = unit.get_owner_player()
		if owner_player != null:
			var flag = owner_player.get("is_neutral")
			if flag != null:
				return bool(flag)
	return false
