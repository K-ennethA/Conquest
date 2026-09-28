extends NetGameRules
class_name CommandApplier

## The battle's command seam: [NetGameRules] (THE one deterministic apply path) bound
## to the live battle, under the name the battle / replay code has always used.
##
## Installed on [NetSession] by GameWorldManager for EVERY battle (solo, hotseat,
## networked) via [method NetSession.install_command_seam]. Replay playback
## ([ReplayDriver]) drives recorded commands through [method apply_command]; a network
## match applies accepted actions through [method NetGameRules.apply_action] on the
## rules object GameModeManager attaches -- the same class, the same code. There is no
## second mutation path: this subclass only adds the command-log entry points.
##
## Unit identity is [NetUnitIds] ("<slot>:<n>"). [method assign_initial_ids] names the
## freshly spawned board; mid-match arrivals are named after every applied command.

## DEPRECATED shim for the old int-id registry API (GameWorldManager's seam setup built
## one and handed it in). Ids are [NetUnitIds] strings now; this only forwards, plus it
## remembers explicitly [method register]ed units so a board double without all_units()
## can still be driven (the applier falls back to it in [method find_unit]).
class UnitRegistry extends RefCounted:
	var _board = null
	var _by_id: Dictionary = {}

	func _live_board():
		return _board if _board != null else (CombatServices.board() if CombatServices != null else null)

	## Name every unit on the live board (NetUnitIds scheme). [param units] is ignored --
	## ids are derived from the board (owner slot, then cell), identically on every peer.
	func assign_map_units(_units: Array = [], _start_id: int = 1) -> void:
		NetUnitIds.assign(_live_board(), true)

	## Bind [param unit] to [param net_id] (stored as its NetUnitIds String).
	func register(unit, net_id) -> void:
		if unit == null:
			return
		var id := str(net_id)
		_by_id[id] = unit
		(unit as Object).set_meta(NetUnitIds.META, id)

	func unit_for(net_id):
		var id := str(net_id)
		var u = _by_id.get(id, null)
		if u != null and is_instance_valid(u):
			return u
		return NetUnitIds.find(_live_board(), id)

	func id_for(unit) -> String:
		return NetUnitIds.id_of(unit)


## Kept for callers that still pass a registry; ids live on the units themselves.
var registry: UnitRegistry = null


## [param p_registry] and [param p_match_rng] are optional (see [UnitRegistry]).
## [param board_provider] / [param turn_provider] default to the LIVE battle
## (CombatServices board, active turn system); tests inject their own.
func _init(p_registry: UnitRegistry = null, p_match_rng = null,
		board_provider: Callable = Callable(), turn_provider: Callable = Callable()) -> void:
	super(board_provider if board_provider.is_valid() else NetGameRules.live_board_provider(),
		turn_provider if turn_provider.is_valid() else NetGameRules.live_turn_provider(), 0)
	registry = p_registry if p_registry != null else UnitRegistry.new()
	match_rng = p_match_rng


## Board lookup first; then a unit [UnitRegistry.register]ed by hand (headless doubles).
func find_unit(unit_id: String):
	var u = super(unit_id)
	if u == null and registry != null:
		u = registry.unit_for(unit_id)
	return u


## Apply one resolved [param cmd] (any shape [method NetProtocol.is_well_formed] accepts,
## i.e. a recorded / replayed command) through THE apply path. [param board] and
## [param ctx] ({ "turn_system": obj }) override the live providers for this call
## (headless replays / tests). Returns { ok, type, seq, reason, events, ... }.
func apply_command(cmd: Dictionary, board_override = null, ctx = null) -> Dictionary:
	if not NetProtocol.is_well_formed(cmd):
		return {"ok": false, "type": int(cmd.get(NetProtocol.KEY_TYPE, -1)),
			"seq": int(cmd.get(NetProtocol.KEY_SEQ, 0)), "reason": NetProtocol.INTENT_MALFORMED, "events": []}
	var saved_board := _board_provider
	var saved_turn := _turn_provider
	if board_override != null:
		_board_provider = func(): return board_override
	if ctx is Dictionary and (ctx as Dictionary).has("turn_system"):
		var ts = ctx["turn_system"]
		_turn_provider = func(): return ts
	var result := apply_action(cmd)
	_board_provider = saved_board
	_turn_provider = saved_turn
	return result


## The desync / replay checksum over [param board_override] (or the live board).
func hash_match_state(board_override = null) -> int:
	if board_override == null:
		return state_digest()
	var saved := _board_provider
	_board_provider = func(): return board_override
	var h := state_digest()
	_board_provider = saved
	return h
