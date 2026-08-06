extends MoveEffect
class_name VoidstepEffect

## ONE MOVE, TWO RESOLUTIONS, CHOSEN BY WHAT IS AIMED AT (Duskmaw's Voidstep).
##
##   * aim a FREE cell within [member place_range] -> PLANT a void spot there. The move's
##     ordinary (short) authored cooldown starts, so anchors go down cheaply.
##   * aim a cell already holding ONE OF THIS CASTER'S OWN SPOTS -> TELEPORT the caster
##     onto it. The move's remaining cooldown is then SET to [member teleport_cooldown]
##     (long), through [method MovesetController.cooldown_started].
##
## WHY ONE MOVE. The two halves are the same fantasy and share one slot; splitting them
## would eat a second moveset entry and force the player to swap tools mid-plan. Which
## half resolves is a pure function of the aim cell and the board, so it is decided
## identically on every lockstep peer and in every replay -- the COMMAND is still "cast
## slot N at cell C" and nothing new is transmitted.
##
## THE SAME RESOURCE IS ALSO THE MOVE'S AIM RULE. This effect is referenced from its own
## move's [member TargetingPattern.aim_rule], so [method allows_aim] -- the one function
## that says which cells are legal -- is what the targeting HIGHLIGHT, the executor's
## validation and this resolution all read. There is deliberately no second copy of
## "where may Voidstep be aimed": a retune here moves the lit tiles with it.
##
## SPOT LIFECYCLE, all of it deterministic:
##   * a spot is a per-cast DUPLICATE of [member spot] laid into the APPLIED tile-effect
##     layer (the machinery [ApplyTileEffect] uses), stamped with its placer's player AND
##     with this caster's identity + a per-caster sequence number;
##   * its expiry is AUTHORED HERE ([member lifetime_turns]), not mode-driven, so it runs
##     out on the same schedule in a plain skirmish as it does inside Siege. The sweep
##     that honours it is [method TileEffectSystem.expire_placed_effects], driven on every
##     turn boundary by [method TileEffectSystem.setup];
##   * at most [member max_spots] live at once PER CASTER -- planting one more evicts the
##     OLDEST (lowest sequence, ties broken by row-major cell order);
##   * spots do NOT die with their caster. An anchor is terrain the caster left behind,
##     which is cheap to reason about and lets a killed unit's marks still shape the board
##     until they time out.
##
## EVERY ANCHOR IS SPENT, ONE WAY OR ANOTHER. There are four ways one leaves the board and
## they all run through [method CombatServices.remove_tile_effect], so the state cleared and
## the marker pulled are identical whichever it was:
##   * STEPPED THROUGH -- a teleport CONSUMES the anchor it arrives on. A tear is a one-way
##     door; keeping an escape route means keeping planting;
##   * STOMPED -- an ENEMY (or a neutral: anyone not on the placer's side) that ENTERS the
##     cell destroys it outright, by any movement at all. That is the counterplay, and it is
##     an authored tile rule ([member TileEffectResource.destroyed_by_hostile_entry]) run at
##     the tile-entry seam, not special-cased here;
##   * EVICTED -- a fourth placement pushes the oldest off;
##   * EXPIRED -- the authored clock runs out.
## The caster's OWN side never breaks an anchor by standing on it: an occupied anchor is
## merely closed as a destination ([method allows_aim]) and opens again when they step off.
## Each of the four frees one of the caster's three slots the moment it happens, because
## [method own_spot_cells] reads the live board rather than a tally.
##
## QUIET FAILURES (CONQUEST.md rule 1). An impossible aim -- a spot somebody is standing
## on, a placement onto blocked or occupied ground -- is a logged no-op, never an engine
## error, so a stale aim or a mock board can never break a move mid-resolution.

## The anchor laid onto a cell. A pure marker: it has no effects and no rule flags, so it
## does nothing whatsoever to a unit standing on it -- its whole job is to BE somewhere.
@export var spot: TileEffectResource

## How far a spot may be PLANTED from the caster (Manhattan). The move's own
## [member TargetingPattern.max_range] is the TELEPORT reach and is deliberately larger;
## this is the tighter half of [method allows_aim].
@export var place_range: int = 4

## Full turns a planted spot survives before the expiry sweep takes it. Authored here
## rather than read from the active mode: an anchor's life is part of the MOVE's balance,
## not of a mode's pacing, so it is the same number in every mode and in none.
@export var lifetime_turns: int = 12

## How many spots ONE caster may hold at once. Planting past the cap evicts the oldest.
@export var max_spots: int = 3

## Cooldown (in turns) a TELEPORT starts, replacing the move's short authored cooldown.
@export var teleport_cooldown: int = 4

## Meta stamped on each placed copy: the [method Object.get_instance_id] of the unit that
## planted it. Per-UNIT rather than per-player, because the cap is per caster and two
## Duskmaws on one team must not share three anchors between them.
const OWNER_META := &"voidstep_caster_id"

## Meta stamped on each placed copy: this caster's placement sequence number, which is
## what makes "the oldest" an exact answer rather than a guess at a shared round counter.
const SEQ_META := &"voidstep_seq"

## Meta held on the CASTER: the next sequence number it will stamp. Per-unit state, so
## nothing static is introduced (a static counter would be global state every suite has
## to reset -- tests/README rule 3) and it dies with the unit.
const CASTER_SEQ_META := &"voidstep_next_seq"

## The id the placed anchors carry, read back when the board is scanned for them. Taken
## from [member spot] at runtime; this is the fallback for a build where the resource
## failed to load.
const SPOT_ID := &"void_spot"


func apply(ctx: MoveContext) -> void:
	if ctx == null or ctx.caster == null or ctx.board == null or spot == null:
		return
	if not ctx.board.has_method("cell_of"):
		return
	var origin: Vector2i = ctx.board.cell_of(ctx.caster)
	var aim: Vector2i = ctx.aim_cell
	# THE BRANCH, and the only one. Standing on one of your own anchors is the teleport;
	# everything else the aim rule let through is a placement.
	if is_own_spot_cell(ctx.caster, aim, ctx.board):
		_teleport(ctx, origin, aim)
	else:
		_place(ctx, origin, aim)


func describe() -> String:
	if description_override != "":
		return description_override
	return "Plant a void spot within %d, or step to one of your own (max %d, %d turns)" \
		% [place_range, max_spots, lifetime_turns]


# --- The aim rule -------------------------------------------------------------
#
# Consulted by [method TargetingPattern.is_aim_allowed], which the targeting highlight
# ([method UnitActionsPanel._compute_in_range_aim_cells]) and [MoveExecutor] both validate
# through -- so the cells that light up are exactly the cells that resolve.


## May [param caster] standing on [param origin] aim its Voidstep at [param aim]?
##
## Two ways to say yes, and nothing else:
##   * [param aim] holds one of [param caster]'s OWN spots and NOBODY is standing on it
##     (a body parked on an anchor closes it until it moves off) -- the teleport;
##   * [param aim] is within [member place_range] and is ground the caster could stand on
##     -- the placement.
## The move's own [member TargetingPattern.max_range] has already bounded the distance by
## the time this is called, so this only ever narrows.
func allows_aim(origin: Vector2i, aim: Vector2i, caster, board) -> bool:
	if caster == null or board == null:
		return false
	if is_own_spot_cell(caster, aim, board):
		return _free_cell(aim, caster, board) and aim != origin
	if _manhattan(origin, aim) > place_range:
		return false
	return _free_cell(aim, caster, board) and aim != origin


# --- Resolution ---------------------------------------------------------------

func _place(ctx: MoveContext, origin: Vector2i, cell: Vector2i) -> void:
	if _manhattan(origin, cell) > place_range or not _free_cell(cell, ctx.caster, ctx.board):
		ctx.log_event({ "effect": "voidstep", "mode": "place", "cell": cell,
			"placed": false, "reason": "invalid_cell" })
		return
	var services = _combat_services()
	if services == null or not services.has_method("add_tile_effect"):
		ctx.log_event({ "effect": "voidstep", "mode": "place", "cell": cell,
			"placed": false, "reason": "no_tile_effect_layer" })
		return

	# THE PER-CAST COPY. The authored resource is loaded once and handed to every caster,
	# so the owner, the placement record and this caster's stamp all have to land on a
	# duplicate (CONQUEST.md rule 7). Shallow -- a spot has no sub-effects to deepen.
	var placed: TileEffectResource = spot.duplicate()
	if ctx.caster.has_method("get_owner_player"):
		placed.owner_player = ctx.caster.get_owner_player()
	# FROZEN AT PLACEMENT, exactly as a mode-driven trap expiry is: the round it goes down
	# plus this move's authored lifetime, computed once and never re-read. Two peers that
	# planted the same anchor on the same round agree on the round it vanishes without
	# exchanging anything.
	placed.stamp_placement(ModeTuning.current_round(), lifetime_turns)
	placed.set_meta(OWNER_META, ctx.caster.get_instance_id())
	var seq: int = _next_seq(ctx.caster)
	placed.set_meta(SEQ_META, seq)

	# THE CAP, applied BEFORE the new anchor goes down so the board is never briefly over
	# it (an overlay rebuild between the two would flash a fourth pip).
	var evicted = _evict_oldest_if_full(ctx, services)

	services.add_tile_effect(cell, placed)
	ctx.log_event({
		"effect": "voidstep",
		"mode": "place",
		"cell": cell,
		"placed": true,
		"seq": seq,
		"expires_on_round": placed.expires_on_round,
		"evicted_cell": evicted,
	})


func _teleport(ctx: MoveContext, from: Vector2i, to: Vector2i) -> void:
	if from == to or not _free_cell(to, ctx.caster, ctx.board) \
			or not ctx.board.has_method("move_unit"):
		ctx.log_event({ "effect": "voidstep", "mode": "teleport", "from": from, "to": to,
			"moved": false, "reason": "blocked" })
		return

	ctx.board.move_unit(ctx.caster, to)
	# THE ONE MOVE-APPLY SEAM. Every mover in the game announces itself on
	# GameEvents.unit_moved and nowhere else, which is what makes the terrain side of a
	# relocation happen at all: ON_EXIT on the cell left, ON_ENTER on the cell landed on,
	# and any trap waiting on the anchor springs the instant the caster arrives. Emitting
	# it is therefore the whole integration -- nothing here re-implements a tile rule.
	_announce_move(ctx.caster, from, to)
	# THE ANCHOR IS SPENT. Stepping through a tear closes it: an anchor is a ONE-WAY door,
	# so a Duskmaw that wants to keep escaping has to keep planting. Deliberately AFTER the
	# announcement, so the ground the caster arrived on resolved against a board that still
	# held the anchor -- the same "the ground gets its say first" order the stomp follows.
	var spent = _consume_spot(ctx, to)
	# THE LONG COOLDOWN, set as RESOLUTION state rather than as an authored number: the
	# move's own `cooldown` is the short PLACE cost, and the caller's on_used will not
	# shorten a wait resolution already started (see MovesetController.on_used). It lands
	# on every peer because it happens inside the deterministic resolution both peers run.
	_start_teleport_cooldown(ctx.caster, ctx.move)
	ctx.log_event({ "effect": "voidstep", "mode": "teleport", "from": from, "to": to,
		"moved": true, "cooldown": teleport_cooldown, "consumed": spent != null })


## Take the anchor on [param cell] off the board, through the SAME
## [method CombatServices.remove_tile_effect] path an eviction, an expiry and a stomp all
## use -- so a spent anchor leaves identically and the overlay pulls its pip for the same
## reason. Returns the removed placement, or null when there was nothing to spend.
func _consume_spot(ctx: MoveContext, cell: Vector2i):
	var services = _combat_services()
	if services == null or not services.has_method("remove_tile_effect"):
		return null
	var spot_here = _spot_on(services, cell, ctx.caster)
	if spot_here == null:
		return null
	services.remove_tile_effect(cell, spot_here)
	return spot_here


## Set the caster's cooldown for [param move] to [member teleport_cooldown]. Null-safe and
## duck-typed end to end: a mock caster, a unit with no [MovesetController], or a
## controller predating [method MovesetController.cooldown_started] simply takes nothing.
func _start_teleport_cooldown(caster, move) -> void:
	if caster == null or move == null or not caster.has_method("get_moveset_controller"):
		return
	var controller = caster.get_moveset_controller()
	if controller == null or not is_instance_valid(controller):
		return
	if controller.has_method("cooldown_started"):
		controller.cooldown_started(move, teleport_cooldown)


## Announce the relocation on [signal GameEvents.unit_moved], in the GRID space that
## signal's listeners assume -- Vector3(col, 0, row), never metres (CONQUEST.md rule 5).
##
## Only a real [Unit] is announced: the signal is TYPED (Unit, Vector3, Vector3) and a
## duck-typed mock would be rejected by the engine, so a unit-test board relocates through
## `move_unit` alone exactly as a leap does. Mirrors
## [method CommandApplier._emit_unit_moved].
static func _announce_move(unit, from: Vector2i, to: Vector2i) -> void:
	if not (unit is Unit):
		return
	if typeof(GameEvents) != TYPE_OBJECT or GameEvents == null:
		return
	GameEvents.unit_moved.emit(unit, Vector3(from.x, 0, from.y), Vector3(to.x, 0, to.y))


# --- The caster's own spots ---------------------------------------------------


## Every cell currently holding one of [param caster]'s void spots, in ROW-MAJOR order.
##
## Walks the APPLIED tile-effect layer only -- map-authored terrain is a different layer
## and is never enumerated -- so this can never mistake ground for an anchor. The order is
## stated rather than inherited so every caller (the eviction, the tests, a future UI)
## sees the same list on every machine.
static func own_spot_cells(caster, _board = null) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if caster == null:
		return out
	var services = _combat_services()
	if services == null or not services.has_method("applied_effect_cells"):
		return out
	var cells: Array = services.applied_effect_cells()
	cells.sort_custom(_cell_before)
	for cell in cells:
		if _spot_on(services, cell, caster) != null:
			out.append(cell)
	return out


## True when [param cell] holds one of [param caster]'s own void spots.
static func is_own_spot_cell(caster, cell: Vector2i, _board = null) -> bool:
	if caster == null:
		return false
	var services = _combat_services()
	if services == null or not services.has_method("applied_tile_effects_at"):
		return false
	return _spot_on(services, cell, caster) != null


## [param caster]'s spot on [param cell], or null. The APPLIED layer's own array order
## decides which one wins when a cell somehow carries two (it cannot today: a placement
## refuses a cell that already holds one of this caster's spots, because that cell is the
## TELEPORT branch).
static func _spot_on(services, cell: Vector2i, caster):
	var owner_id: int = caster.get_instance_id()
	for te in services.applied_tile_effects_at(cell):
		if te == null or not (te is Object):
			continue
		if not (te as Object).has_meta(OWNER_META):
			continue
		if int((te as Object).get_meta(OWNER_META)) != owner_id:
			continue
		return te
	return null


## Drop this caster's OLDEST spot when it is already at [member max_spots], so the new one
## fits. Returns the evicted cell, or null when nothing had to go.
##
## Oldest = lowest [constant SEQ_META]; a tie (impossible today, but the rule is stated
## rather than assumed) falls back to row-major cell order, which is the order
## [method own_spot_cells] already walks in. Pure arithmetic on frozen stamps: no RNG, no
## clock, so every peer evicts the same anchor.
func _evict_oldest_if_full(ctx: MoveContext, services):
	var cells: Array[Vector2i] = own_spot_cells(ctx.caster)
	if cells.size() < maxi(1, max_spots):
		return null
	var oldest_cell = null
	var oldest_seq: int = 1 << 62
	for cell in cells:
		var te = _spot_on(services, cell, ctx.caster)
		if te == null:
			continue
		var seq: int = int((te as Object).get_meta(SEQ_META, 0))
		if oldest_cell == null or seq < oldest_seq:
			oldest_cell = cell
			oldest_seq = seq
	if oldest_cell == null:
		return null
	var doomed = _spot_on(services, oldest_cell, ctx.caster)
	# THE SAME REMOVAL PATH an expired or a spent placement takes, so an evicted anchor
	# leaves the board identically -- same state cleared, same tile_effects_changed raised,
	# same marker pulled off the cell by the overlay.
	if services.has_method("remove_tile_effect"):
		services.remove_tile_effect(oldest_cell, doomed)
	ctx.log_event({ "effect": "voidstep", "mode": "evict", "cell": oldest_cell, "seq": oldest_seq })
	return oldest_cell


## The next placement sequence number for [param caster], advancing its counter.
static func _next_seq(caster) -> int:
	var next: int = 1
	if caster is Object and (caster as Object).has_meta(CASTER_SEQ_META):
		next = int((caster as Object).get_meta(CASTER_SEQ_META))
	if caster is Object:
		(caster as Object).set_meta(CASTER_SEQ_META, next + 1)
	return next


# --- Board helpers ------------------------------------------------------------


## Could [param caster] stand on [param cell] right now? Prefers the board's own
## [code]can_fit[/code] (bounds + blocking terrain + other living units + footprint) and
## falls back to whichever individual queries a lighter board exposes -- the same ladder
## [LeapEffect] and [TargetingPattern] climb, so all three agree about a legal landing.
static func _free_cell(cell: Vector2i, caster, board) -> bool:
	if board == null:
		return false
	if board.has_method("can_fit"):
		return bool(board.can_fit(caster, cell))
	if board.has_method("in_bounds") and not bool(board.in_bounds(cell)):
		return false
	if board.has_method("is_blocked") and bool(board.is_blocked(cell)):
		return false
	if board.has_method("units_at"):
		for unit in board.units_at(cell):
			if unit != null and unit != caster:
				return false
	return true


static func _combat_services():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("CombatServices")
	return null


## Row-major cell order, spelled out where it is depended on (the twin of
## [method TileEffectSystem._cell_before]).
static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
