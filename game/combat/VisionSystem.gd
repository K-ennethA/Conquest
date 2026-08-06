extends Node
class_name VisionSystem

## FOG OF WAR: who can see what, derived from board state alone.
##
## THE WHOLE SYSTEM IS A PURE FUNCTION OF THE BOARD -- unit positions, the tile effects on
## the cells they stand on, the map's own [member MapResource.fog_of_war] flag, and a small
## set of REVEAL records stamped with the turn they run out on. There is no RNG, no wall
## clock and no scene order anywhere in it, so two lockstep peers computing vision from the
## same board get byte-identical answers and a replay re-derives them exactly. Nothing about
## vision is ever transmitted: it is recomputed, never received.
##
## OFF BY DEFAULT, AND OFF MEANS GONE. Every map authored before fog existed reports
## [method fog_enabled] false, and with fog off EVERY query here answers "visible":
## [method is_cell_visible] and [method is_unit_visible] return true, [method visible_cells]
## returns the whole board, and the gameplay seams that consult this system
## ([method MoveContext._matches_target_kind], [method MoveExecutor.preview_vs],
## [BotController]) short-circuit to exactly the code they ran before this file existed.
## That is the pin: fog off is not "fog with a big radius", it is no fog system at all.
##
## THE RULES (all data-tunable, none of them a constant in a call site):
##
##   1. SIGHT. Every unit lights the CHEBYSHEV square of radius [constant DEFAULT_SIGHT_RANGE]
##      around each cell it covers; a character may override that with
##      [member CharacterResource.sight_range]. A team sees the UNION of its units' sight, and
##      its OWN units are always visible to it whatever the geometry says.
##
##      CHEBYSHEV, not Manhattan. A Manhattan radius is a diamond, which leaves the four
##      diagonal directions blind at a distance the four cardinals see clearly -- on a square
##      grid that reads as a bug rather than as a rule. The square block is also the shape
##      [constant CombatTypes.AreaShape.SQUARE] already means by "radius" in this codebase, so
##      "radius 4" means one thing across the whole game. Move RANGE stays Manhattan: reach and
##      sight are different questions and always have been.
##
##   2. CONCEALMENT. A unit standing on a cell carrying a
##      [member TileEffectResource.conceals_occupants] effect is hidden even inside a seer's
##      sight radius, UNLESS a unit of the looking side is within
##      [constant CONCEAL_ADJACENCY] cells of it -- the classic thicket-ambush rule: you cannot
##      see into the smoke from across the field, but you can see into it from its edge.
##
##      IT IS A FLAG ON THE EFFECT, NOT A LIST OF TERRAIN. That is the whole "smaller fog of
##      war on moves" hook: a smoke-cloud move needs no vision code at all, it places a tile
##      effect carrying the flag through the ordinary [ApplyTileEffect] and the placement /
##      expiry machinery that already exists. `smoke_veil.tres` is the demonstration.
##
##   3. REVEAL ON ATTACK. A hidden unit that resolves a HOSTILE move gives itself away: it is
##      marked visible to everybody for [constant REVEAL_TURNS] turn boundaries, so the side it
##      just hit can hit back. Without this a unit sitting in a veil would be an attacker that
##      cannot be answered, which is not a mechanic, it is a bug with a description.
##
##      MARKED BEFORE THE DAMAGE IS ANNOUNCED. [method MoveExecutor.execute] calls
##      [method note_hostile_move] after validation and BEFORE it applies a single effect, so
##      by the time [code]GameEvents.damage_dealt[/code] fires the attacker is already visible
##      and the victim's side sees the blow land with someone behind it.
##
##      ONLY A HOSTILE RESOLUTION REVEALS ([method is_hostile_move]): walking does not, and
##      neither does planting a tile effect, a heal or a self-buff. Laying the veil you then
##      hide in must not light you up.
##
## CACHE. Per player slot, invalidated wholesale on every event that can move a unit, change
## the ground, or turn the clock -- [method invalidate] then re-emits [signal vision_changed]
## and presentation re-reads. Wholesale rather than per-cell on purpose: the recompute is a
## few hundred dictionary writes and an incremental invalidation is where the desync between
## what the board is and what the screen shows would live.

## Emitted after ANY recompute-worthy change (a unit moved, spawned or died, a tile effect was
## placed or expired, a turn boundary passed, a reveal was stamped or ran out, or the map
## changed). The cache is already dropped when this fires, so a listener that re-queries gets
## fresh answers. Presentation re-reads on this and nothing else.
signal vision_changed

## Sight radius (Chebyshev) a unit lights when its character declares none.
const DEFAULT_SIGHT_RANGE: int = 4

## How close a seer must be to see a CONCEALED unit -- 1 = the eight surrounding cells.
const CONCEAL_ADJACENCY: int = 1

## Turn boundaries a REVEAL survives. 2 covers the rest of the attacker's own turn plus the
## whole of the answering side's next turn, which is the "revealed for a turn or so" the rule
## is written to mean; it expires at the start of the turn after that.
const REVEAL_TURNS: int = 2

# --- The live instance --------------------------------------------------------
#
# Battle-mounted (a child of GameWorldManager, exactly like TileEffectSystem) rather than an
# autoload, because vision is per-BATTLE state and must not survive one: a stale lit set from
# the previous map is worse than no fog at all. But the seams that consult it -- a static
# MoveExecutor, a RefCounted BotController, a MoveContext with no scene tree -- have no handle
# to reach a node with, so the instance registers itself here on _ready and clears itself on
# _exit_tree, and every seam goes through a NULL-SAFE static that answers "visible" when there
# is no battle. That is what keeps every unit suite in the project running unchanged.

static var _active = null


## The live instance, or null outside a battle (headless suites, menus, the map editor).
## Callers MUST null-check -- or better, use the statics below, which already do.
static func active():
	if _active != null and is_instance_valid(_active):
		return _active
	return null


## The loaded [MapResource] this battle is being fought on -- the source of
## [method fog_enabled]. Null until [method set_map] is called.
var _map = null

## player slot ([int]) -> Dictionary of lit cells ([Vector2i] -> true). Dropped wholesale by
## [method invalidate].
var _cache: Dictionary = {}

## The "fog off" full-board answer, built once per map (see [method _whole_board]).
var _whole_board_cache: Dictionary = {}

## REVEAL RECORDS: unit instance id ([int]) -> { "ref": WeakRef, "until": int }, where "until"
## is the [member _turn_index] the record stops applying on. Keyed on the id (not the object)
## so a freed unit can never keep a strong reference alive, and stamped with a FROZEN turn
## number for the same reason a placed trap's expiry is frozen -- retuning nothing later can
## move a reveal already on the board.
var _reveals: Dictionary = {}

## Monotonic count of turn boundaries this battle has seen. Driven by the ACTIVE turn system's
## turn_started (CONQUEST.md rule 2) -- never PlayerManager's, which do not fire on AI turns,
## so a reveal stamped during the enemy phase would otherwise never run out.
var _turn_index: int = 0

## The turn system [method setup] is currently riding, so it can be dropped cleanly.
var _watched_ts = null

## Optional injected board, winning over the live [CombatServices] one when set. The same
## escape hatch [member TileEffectSystem.tile_effects] is: it lets a suite drive the whole
## system against a mock board with no autoload, no scene tree and no map load. Left null in
## the live game, which reads the one shared adapter like everything else.
var _board_override = null


## Point this system at [param board] instead of the live [CombatServices] adapter (tests /
## headless harnesses). Pass null to go back to the live board.
func set_board(board) -> void:
	_board_override = board
	invalidate()


func _ready() -> void:
	_active = self


## The battle is over. Godot would drop these connections when this node is freed anyway, but
## a system torn down between battles while the AUTOLOADS survive would otherwise keep
## recomputing vision for a board it no longer serves -- the same reason [TileEffectSystem]
## unhooks its expiry sweep here. Clearing [member _active] is the load-bearing half: a stale
## instance answering [method active] would hand the next battle the last one's lit set.
func _exit_tree() -> void:
	if _active == self:
		_active = null
	_unwatch_turn_system()
	if typeof(TurnSystemManager) == TYPE_OBJECT and TurnSystemManager != null \
			and TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.disconnect(_on_turn_system_activated)
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null:
		if GameEvents.unit_moved.is_connected(_on_unit_moved):
			GameEvents.unit_moved.disconnect(_on_unit_moved)
		if GameEvents.unit_spawned.is_connected(_on_unit_spawned):
			GameEvents.unit_spawned.disconnect(_on_unit_spawned)
		if GameEvents.unit_eliminated.is_connected(_on_unit_eliminated):
			GameEvents.unit_eliminated.disconnect(_on_unit_eliminated)
	if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null:
		if CombatServices.tile_effects_changed.is_connected(_on_tile_effects_changed):
			CombatServices.tile_effects_changed.disconnect(_on_tile_effects_changed)
		if CombatServices.board_ready.is_connected(_on_board_ready):
			CombatServices.board_ready.disconnect(_on_board_ready)


## Subscribe to everything that can change what anybody can see. Called once by
## [code]GameWorldManager._setup_vision[/code]; idempotent, and a no-op for each autoload a
## headless harness happens not to have (which is what lets a unit suite drive this system by
## hand with [method invalidate] and [method note_turn_started]).
##
## THE INVALIDATION SET, and why each entry is here:
##   * unit_moved / unit_spawned / unit_eliminated -- the lit set is a function of where units
##     stand, so all three change it. unit_moved is also the ONE move-apply seam every mover in
##     the game announces through (the human commit, the AI relocate, CommandApplier on every
##     networked peer and every replay), so subscribing here covers all of them at once.
##   * tile_effects_changed -- a placed or expired CONCEALING effect changes who is hidden
##     without anybody moving. This is the signal a smoke veil's whole life rides.
##   * board_ready -- a fresh board means a fresh battle; the previous map's cache is garbage.
##   * the active turn system's turn_started -- turns the reveal clock.
func setup() -> void:
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null:
		if not GameEvents.unit_moved.is_connected(_on_unit_moved):
			GameEvents.unit_moved.connect(_on_unit_moved)
		if not GameEvents.unit_spawned.is_connected(_on_unit_spawned):
			GameEvents.unit_spawned.connect(_on_unit_spawned)
		if not GameEvents.unit_eliminated.is_connected(_on_unit_eliminated):
			GameEvents.unit_eliminated.connect(_on_unit_eliminated)
	if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null:
		if not CombatServices.tile_effects_changed.is_connected(_on_tile_effects_changed):
			CombatServices.tile_effects_changed.connect(_on_tile_effects_changed)
		if not CombatServices.board_ready.is_connected(_on_board_ready):
			CombatServices.board_ready.connect(_on_board_ready)
	if typeof(TurnSystemManager) == TYPE_OBJECT and TurnSystemManager != null:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated(TurnSystemManager.get_active_turn_system())


# --- The map (the toggle) -----------------------------------------------------

## Point this system at the [MapResource] the battle is being fought on. Fed by
## [code]GameWorldManager._on_map_loaded[/code], so the toggle is a property of the MAP and
## nothing in the engine decides it. Drops the cache and announces.
func set_map(map_resource) -> void:
	_map = map_resource
	_whole_board_cache.clear()
	invalidate()


## The map currently driving this system, or null.
func map():
	return _map


## True when THIS BATTLE'S MAP asked for fog of war. False for every map that predates the
## flag, which is the answer that makes the whole system inert.
func fog_enabled() -> bool:
	if _map == null:
		return false
	var v = _map.get("fog_of_war")
	return v != null and bool(v)


# --- The pinned queries -------------------------------------------------------

## Every cell player [param player_id] can currently see: a SET, [Vector2i] -> true.
##
## READ-ONLY -- this is the live cached dictionary, handed out rather than copied because
## presentation re-reads it on every [signal vision_changed] and a per-call duplicate of a
## 1200-cell map would be pure waste. Do not mutate it.
##
## With fog off this is the whole board (every in-bounds cell the map declares), so a caller
## that intersects against it sees no change at all.
func visible_cells(player_id: int) -> Dictionary:
	if not fog_enabled():
		return _whole_board()
	if _cache.has(player_id):
		return _cache[player_id]
	var lit: Dictionary = _compute_lit(player_id)
	_cache[player_id] = lit
	return lit


## Can player [param player_id] see the GROUND at [param cell]? Always true with fog off.
##
## Ground, deliberately, not "is there anything there": fog hides UNITS, not terrain, so a
## ground-targeted move ([ApplyTileEffect]'s empty-tile cast, Duskmaw's Abyssal Maw) stays
## castable anywhere in its range and this query never gates it.
func is_cell_visible(player_id: int, cell: Vector2i) -> bool:
	if not fog_enabled():
		return true
	return visible_cells(player_id).has(cell)


## Can player [param player_id] see [param unit]? The full rule, in the order it resolves:
##
##   1. fog off                         -> yes (and nothing below is even evaluated);
##   2. it is one of MY OWN units       -> yes, always, whatever the geometry says;
##   3. it is REVEALED (it just attacked from hiding) -> yes, until the record runs out;
##   4. no cell it covers is lit        -> no;
##   5. it stands in CONCEALING ground  -> only if I have a unit within
##                                         [constant CONCEAL_ADJACENCY] of it;
##   6. otherwise                       -> yes.
func is_unit_visible(player_id: int, unit) -> bool:
	if unit == null:
		return false
	if not fog_enabled():
		return true
	var owner_id: int = player_id_of(unit)
	if owner_id >= 0 and owner_id == player_id:
		return true
	if is_revealed(unit):
		return true
	var board = _board()
	if board == null:
		# No board to reason about. Fail OPEN, exactly as every other duck-typed query in the
		# combat module does: inventing invisibility out of a missing world would make units
		# untargetable in harnesses that never asked for fog.
		return true
	var cells: Array = _cells_of(unit, board)
	var lit: Dictionary = visible_cells(player_id)
	var in_sight: bool = false
	for c in cells:
		if lit.has(c):
			in_sight = true
			break
	if not in_sight:
		return false
	if not is_concealed(unit, board):
		return true
	return _has_seer_within(player_id, cells, board, CONCEAL_ADJACENCY)


## True when [param unit] stands on ground that CONCEALS it -- any tile effect on any cell it
## covers that declares [member TileEffectResource.conceals_occupants] and actually
## [method TileEffectResource.applies_to] this unit (so a veil authored as
## enemies-only spares its placer's own side for free).
func is_concealed(unit, board = null) -> bool:
	if unit == null:
		return false
	if board == null:
		board = _board()
	if board == null:
		return false
	for cell in _cells_of(unit, board):
		for te in _tile_effects_at(cell, board):
			if te == null or not te.has_method("conceals"):
				continue
			if te.conceals(unit, board):
				return true
	return false


## [param unit]'s sight radius: its character's [member CharacterResource.sight_range] when it
## declares one, else [constant DEFAULT_SIGHT_RANGE]. Duck-typed end to end so a mock in a unit
## suite can declare a plain `sight_range` property and be seen from exactly that far.
static func sight_range_of(unit) -> int:
	if unit == null:
		return DEFAULT_SIGHT_RANGE
	if unit.has_method("get_sight_range"):
		var direct: int = int(unit.get_sight_range())
		if direct > 0:
			return direct
	var own = unit.get("sight_range")
	if own != null and int(own) > 0:
		return int(own)
	var cr = unit.get("character_resource")
	if cr != null and cr.has_method("get_sight_range"):
		var from_char: int = int(cr.get_sight_range())
		if from_char > 0:
			return from_char
	return DEFAULT_SIGHT_RANGE


# --- Reveal on attack ---------------------------------------------------------

## Stamp [param unit] as REVEALED for the next [constant REVEAL_TURNS] turn boundaries.
## Idempotent in effect: a second attack simply REFRESHES the record onto the later expiry
## rather than stacking a second one (CONQUEST.md rule 6).
func mark_revealed(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	_reveals[unit.get_instance_id()] = {
		"ref": weakref(unit),
		"until": _turn_index + REVEAL_TURNS,
	}
	# No cache to drop -- a reveal changes is_unit_visible, not the lit set -- but presentation
	# has to re-read, so the signal still goes out.
	vision_changed.emit()


## True while [param unit] is giving itself away. Pure arithmetic on the frozen record, so
## every peer and every replay reveals and un-reveals on exactly the same turn.
func is_revealed(unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var rec = _reveals.get(unit.get_instance_id(), null)
	if not (rec is Dictionary):
		return false
	return _turn_index < int((rec as Dictionary)["until"])


## Drive the reveal clock one turn boundary on, dropping whatever ran out. Wired to the active
## turn system's turn_started by [method setup]; PUBLIC so a unit suite can turn the handle
## itself without standing up a turn system.
func note_turn_started() -> void:
	_turn_index += 1
	_prune_reveals()
	invalidate()


## True when [param move] is a HOSTILE resolution -- one that damages, or one aimed at ENEMIES
## at all (a pure debuff still gives you away). Classified off the move's own DATA, never off a
## move id, and MODE-AWARE like every other classifier in the codebase: a two-mode move is
## judged on the mode its caster currently has in force.
##
## What this deliberately does NOT catch, because a designer would be right to be annoyed if it
## did: walking, a heal, a self-buff, and PLACING A TILE EFFECT on empty ground. Laying the
## veil you are about to hide in must not be the thing that lights you up.
static func is_hostile_move(move, caster = null) -> bool:
	if move == null:
		return false
	for e in move.effects_for(caster):
		if DamageMath.is_damage_effect(e):
			return true
	var pattern = move.targeting_for(caster)
	return pattern != null and int(pattern.target_kind) == CombatTypes.TargetKind.ENEMY


# --- The null-safe statics every gameplay seam goes through -------------------
#
# Each of these answers the pre-fog answer when there is no battle, no map, or no fog on the
# map, so a caller can be written as an unconditional line and still be byte-identical to what
# it was. That is deliberate: a seam guarded by `if fog then ... else ...` is a seam where the
# two branches drift.


## THE GATHER GATE. May [param viewer]'s side act on [param unit] at all?
##
## True whenever there is no fog to speak of. With fog on it is [method is_unit_visible]
## evaluated for the VIEWER'S OWN SIDE -- which is what makes this correct under lockstep and
## in replays without a word of network code: the acting unit named by a command is the same
## unit on every peer, so every peer resolves the gather through the same side's vision and
## reaches the same targets. A viewer with no owner (a neutral, a mock) sees everything.
static func gatherable(viewer, unit) -> bool:
	var vs = active()
	if vs == null:
		return true
	return vs.can_see(viewer, unit)


## [method gatherable]'s instance half: can [param viewer]'s SIDE see [param unit]?
func can_see(viewer, unit) -> bool:
	if not fog_enabled():
		return true
	if viewer == null:
		return true
	var pid: int = player_id_of(viewer)
	if pid < 0:
		return true
	return is_unit_visible(pid, unit)


## THE REVEAL SEAM. Called by [method MoveExecutor.execute] after validation and before a
## single effect is applied, so the mark lands ahead of the damage announcement (see the class
## note). A no-op outside a battle, with fog off, or for a move that is not hostile.
static func note_hostile_move(caster, move) -> void:
	var vs = active()
	if vs == null or caster == null or move == null:
		return
	if not vs.fog_enabled():
		return
	if not is_hostile_move(move, caster):
		return
	vs.mark_revealed(caster)


## The player slot owning [param unit], or -1 when it has none (an unowned mock, a
## not-yet-adopted spawn). Duck-typed through the same `get_owner_player` every other
## allegiance query in the combat module uses.
static func player_id_of(unit) -> int:
	if unit == null:
		return -1
	var owner = null
	if unit.has_method("get_owner_player"):
		owner = unit.get_owner_player()
	else:
		owner = unit.get("owner_player")
	if owner == null:
		return -1
	var pid = owner.get("player_id")
	if pid == null:
		return -1
	return int(pid)


# --- Cache + invalidation -----------------------------------------------------

## Drop every cached lit set and announce. The ONE invalidation path -- every subscriber below
## funnels into it, so there is no second way for the cache and the board to disagree.
func invalidate() -> void:
	_cache.clear()
	vision_changed.emit()


func _on_unit_moved(_unit = null, _from = null, _to = null) -> void:
	invalidate()


func _on_unit_spawned(_unit = null, _runtime: bool = false) -> void:
	invalidate()


func _on_unit_eliminated(unit = null, _eliminator = null) -> void:
	# A dead unit's reveal record is dead too. Dropped by id, so this is safe even once the
	# node is on its way out of the tree.
	if unit != null and is_instance_valid(unit):
		_reveals.erase(unit.get_instance_id())
	invalidate()


func _on_tile_effects_changed(_cell: Vector2i = Vector2i.ZERO) -> void:
	invalidate()


func _on_board_ready() -> void:
	invalidate()


func _on_turn_system_activated(ts) -> void:
	if _watched_ts == ts:
		return
	_unwatch_turn_system()
	_watched_ts = ts
	if ts != null and is_instance_valid(ts) and not ts.turn_started.is_connected(_on_turn_started):
		ts.turn_started.connect(_on_turn_started)


func _unwatch_turn_system() -> void:
	if _watched_ts != null and is_instance_valid(_watched_ts) \
			and _watched_ts.turn_started.is_connected(_on_turn_started):
		_watched_ts.turn_started.disconnect(_on_turn_started)
	_watched_ts = null


func _on_turn_started(_player = null) -> void:
	note_turn_started()


func _prune_reveals() -> void:
	var dead: Array = []
	for key in _reveals.keys():
		var rec = _reveals[key]
		if not (rec is Dictionary):
			dead.append(key)
			continue
		var ref = (rec as Dictionary)["ref"]
		if ref == null or (ref as WeakRef).get_ref() == null:
			dead.append(key)
			continue
		if _turn_index >= int((rec as Dictionary)["until"]):
			dead.append(key)
	for key in dead:
		_reveals.erase(key)


# --- Computation --------------------------------------------------------------

## The union of every cell player [param player_id]'s units light. Deterministic by
## construction: a set union does not care about order, and the units are walked in row-major
## cell order anyway so a debugger trace reads the same on every peer.
func _compute_lit(player_id: int) -> Dictionary:
	var lit: Dictionary = {}
	var board = _board()
	if board == null:
		return lit
	for unit in _sorted_units(board):
		if player_id_of(unit) != player_id:
			continue
		var radius: int = maxi(0, sight_range_of(unit))
		for anchor in _cells_of(unit, board):
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					var cell: Vector2i = anchor + Vector2i(dx, dy)
					if not _in_bounds(cell, board):
						continue
					lit[cell] = true
	return lit


## True when any of [param player_id]'s units stands within [param radius] (Chebyshev) of any
## of [param cells] -- the "somebody is close enough to see into the thicket" test.
func _has_seer_within(player_id: int, cells: Array, board, radius: int) -> bool:
	for seer in _sorted_units(board):
		if player_id_of(seer) != player_id:
			continue
		for a in _cells_of(seer, board):
			for b in cells:
				if maxi(absi(a.x - b.x), absi(a.y - b.y)) <= radius:
					return true
	return false


## Every in-bounds cell the map declares -- the "fog off" answer for [method visible_cells].
## Built once per map and held, because a caller that intersects against it on a fogless map
## would otherwise rebuild 1200 entries on every read for an answer that cannot change.
##
## Empty when there is no map to enumerate, which is the harness case; [method is_cell_visible]
## still answers true there because it short-circuits on [method fog_enabled] first.
func _whole_board() -> Dictionary:
	if not _whole_board_cache.is_empty():
		return _whole_board_cache
	var size: Vector2i = _map_size()
	for x in range(size.x):
		for y in range(size.y):
			_whole_board_cache[Vector2i(x, y)] = true
	return _whole_board_cache


## The loaded map's dimensions, or [code]Vector2i.ZERO[/code] when there is no map.
func _map_size() -> Vector2i:
	if _map == null:
		return Vector2i.ZERO
	var w = _map.get("width")
	var h = _map.get("height")
	return Vector2i(int(w) if w != null else 0, int(h) if h != null else 0)


## Is [param cell] on the board at all? THE MAP is the authority when there is one -- its
## width/height are what the tiles were painted from -- and the board's own bounds only answer
## for a harness with no map. Neither present means "unbounded", which is what a mock board
## with no geometry means.
func _in_bounds(cell: Vector2i, board) -> bool:
	var size: Vector2i = _map_size()
	if size.x > 0 and size.y > 0:
		return cell.x >= 0 and cell.x < size.x and cell.y >= 0 and cell.y < size.y
	if board != null and board.has_method("in_bounds"):
		return bool(board.in_bounds(cell))
	return true


func _board():
	if _board_override != null:
		return _board_override
	if typeof(CombatServices) != TYPE_OBJECT or CombatServices == null:
		return null
	if not CombatServices.has_method("board"):
		return null
	return CombatServices.board()


## Every unit on [param board], in row-major cell order then instance id. The ORDER of a set
## union cannot change its contents, so this is not load-bearing for correctness -- it is
## stated so that anything built on top of these walks (a debug overlay, a future incremental
## pass) inherits a deterministic order rather than dictionary insertion order.
func _sorted_units(board) -> Array:
	var out: Array = []
	if board == null or not board.has_method("all_units"):
		return out
	for u in board.all_units():
		if u != null:
			out.append(u)
	var cell_of := func(unit) -> Vector2i:
		return board.cell_of(unit) if board.has_method("cell_of") else Vector2i.ZERO
	out.sort_custom(func(a, b) -> bool:
		var ca: Vector2i = cell_of.call(a)
		var cb: Vector2i = cell_of.call(b)
		if ca.x != cb.x:
			return ca.x < cb.x
		if ca.y != cb.y:
			return ca.y < cb.y
		return a.get_instance_id() < b.get_instance_id())
	return out


static func _cells_of(unit, board) -> Array:
	if unit == null or board == null:
		return []
	if board.has_method("cells_of"):
		var spanned = board.cells_of(unit)
		if spanned is Array and not (spanned as Array).is_empty():
			return spanned
	if board.has_method("cell_of"):
		return [board.cell_of(unit)]
	return []


static func _tile_effects_at(cell: Vector2i, board) -> Array:
	if board != null and board.has_method("tile_effects_at"):
		var arr = board.tile_effects_at(cell)
		if arr is Array:
			return arr
	if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null \
			and CombatServices.has_method("tile_effects_at"):
		return CombatServices.tile_effects_at(cell)
	return []


