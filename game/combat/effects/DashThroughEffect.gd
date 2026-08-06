extends MoveEffect
class_name DashThroughEffect

## A PIERCING DASH: the caster charges in a straight cardinal line THROUGH the enemies in
## its path, damaging each one it passes, and lands on the first free cell beyond the last
## of them (Monster's Shadow Dash).
##
## The relative of [LeapEffect], and deliberately not an extension of it. A leap TELEPORTS
## to a cell the targeting pattern already validated, so the player picks the landing and
## the effect only refuses the impossible. A dash cannot work that way: where it ends is
## DERIVED from what stands in the lane, so the landing is not knowable when the aim is
## chosen. The pattern therefore only picks the DIRECTION (aim any legal cell; the heading
## collapses to a cardinal exactly as LINE and ARC do, via
## [method TargetingPattern._cardinal_dir]) and this walks the lane to find the rest.
##
## THE LANDING RULE, in order, walking outward one cell at a time up to
## [member max_distance]:
##   * TERRAIN THAT CANNOT BE ENTERED (out of bounds, blocked, no room for the caster's
##     footprint) STOPS the dash dead. Nothing beyond it is reachable.
##   * A cell holding only ENEMIES is PIERCED: each of them is marked for damage and the
##     dash continues -- until [member max_pierce] enemies have been passed, after which
##     one more enemy in the way stops it.
##   * A cell holding a NON-ENEMY (an ally, a neutral) BLOCKS: you cannot run through your
##     own side.
##   * A FREE cell is the LANDING -- but only once at least one enemy has been pierced.
##     Before that it is just open ground the caster runs across, so a dash aimed down an
##     empty corridor keeps looking for something to hit rather than stopping one step out.
##
## If the walk ends without a free cell beyond a pierced enemy, THE DASH REFUSES: nothing
## moves, nothing takes damage, and the refusal is a logged VALUE with a reason -- never a
## pushed error (CONQUEST.md rule 1), because "there was no room to land" is an ordinary
## board state, not a bug.
##
## FULLY DETERMINISTIC. Every step of the walk reads only the board and the authored
## numbers; no generator is touched, and the damage LANDS without an accuracy roll (a dash
## is a collision, not a swing -- the same rule a hazard and a status tick follow). So
## lockstep peers and replays resolve the identical landing cell and the identical damage.
##
## DAMAGE runs the ordinary post-mitigation chain ([method DamageMath.apply_scales]) --
## the SAME function the forecast reads -- so a branded victim, an element matchup and a
## defender's reduction all apply exactly as they would to a normal hit, and an
## invulnerable one takes a hard 0. Each hit is announced before it is applied, so a dash
## that kills is credited and fires ON_KILL.
##
## THE CASTER RELOCATES FIRST, then the damage resolves -- the same ordering
## [LeapEffect] documents, so anything chained after this effect reads a caster already
## standing on its landing cell.

## Raw damage per pierced enemy before the caster stat is folded in.
@export var power: int = 10
## Caster stat added to power (e.g. "magic"). Empty = flat power.
@export var scaling_stat: String = "magic"
## Fraction of the scaling stat added to power.
@export var scale: float = 1.0
@export var category: CombatTypes.DamageCategory = CombatTypes.DamageCategory.MAGICAL

## How many enemies the dash may run through. A fourth enemy in the lane stops it.
@export var max_pierce: int = 3
## How far down the lane the walk looks before giving up, in cells.
@export var max_distance: int = 6


func apply(ctx: MoveContext) -> void:
	if ctx == null or ctx.caster == null or ctx.board == null:
		return
	var board = ctx.board
	if not board.has_method("cell_of") or not board.has_method("units_at"):
		return

	var origin: Vector2i = board.cell_of(ctx.caster)
	# Same heading rule as LINE / ARC / the vine lane, so a diagonal aim collapses to the
	# nearer clean face rather than producing a staircase.
	var dir := TargetingPattern._cardinal_dir(origin, ctx.aim_cell)

	var plan := _walk(ctx, origin, dir)
	if not bool(plan["found"]):
		ctx.log_event({
			"effect": "dash",
			"unit": ctx.caster,
			"from": origin,
			"to": origin,
			"moved": false,
			"reason": plan["reason"],
			"pierced": 0,
		})
		return

	var landing: Vector2i = plan["landing"]
	var pierced: Array = plan["pierced"]

	if board.has_method("move_unit"):
		board.move_unit(ctx.caster, landing)
	ctx.log_event({
		"effect": "dash",
		"unit": ctx.caster,
		"from": origin,
		"to": landing,
		"moved": true,
		"reason": "dashed",
		"pierced": pierced.size(),
	})

	_strike(ctx, pierced)


## Walk the lane and decide the outcome. Returns
## { found: bool, landing: Vector2i, pierced: Array, reason: String }.
## [param reason] names the refusal ("blocked_line" / "no_free_cell") so a caller and a
## test can tell the two edge cases apart.
func _walk(ctx: MoveContext, origin: Vector2i, dir: Vector2i) -> Dictionary:
	var board = ctx.board
	var pierced: Array = []
	var reason: String = "no_free_cell"
	for step in range(1, maxi(1, max_distance) + 1):
		var cell: Vector2i = origin + dir * step
		if not _can_enter(ctx, cell):
			# Terrain closed the lane. If we had already pierced someone there was simply
			# no room to land; if we had not, the dash never got going at all.
			reason = "no_free_cell" if not pierced.is_empty() else "blocked_line"
			break
		var blockers: Array = []
		for unit in board.units_at(cell):
			if unit != null and unit != ctx.caster:
				blockers.append(unit)
		if blockers.is_empty():
			if pierced.is_empty():
				continue  # open ground before the first enemy: keep running
			if not _can_land(ctx, cell):
				continue  # no room for this footprint here; keep looking down the lane
			return { "found": true, "landing": cell, "pierced": pierced, "reason": "dashed" }
		if not _all_enemies(ctx, blockers):
			reason = "blocked_line"  # you cannot run through your own side
			break
		if pierced.size() + blockers.size() > maxi(1, max_pierce):
			reason = "blocked_line"  # one enemy too many in the way
			break
		for unit in blockers:
			pierced.append(unit)
	return { "found": false, "landing": origin, "pierced": [], "reason": reason }


## Deal the pass-through damage to everything the dash ran over.
func _strike(ctx: MoveContext, pierced: Array) -> void:
	if pierced.is_empty():
		return
	var raw: int = DamageMath.raw_power(self, ctx.caster)
	for victim in pierced:
		if DamageMath.is_invulnerable(victim):
			# A hard 0, ahead of mitigation and every scale -- logged as NEGATED so the
			# combat log can say the collision was shrugged off rather than printing a 0
			# that reads like a bug. Mirrors [method DamageEffect.apply].
			DamageEffect.announce_damage(ctx.event_bus, ctx.damage_credit(), victim, 0)
			ctx.log_event({
				"effect": "damage",
				"target": victim,
				"amount": 0,
				"category": category,
				"crit": false,
				"negated": true,
			})
			continue
		var mitigated: int = DamageMath.mitigate(raw, victim, category)
		var dealt: int = int(DamageMath.apply_scales(
			mitigated, ctx.caster, victim, ctx.move, ctx.board)["total"])
		# ANNOUNCE BEFORE APPLYING: take_damage can kill outright and the kill is
		# attributed from this signal (see [method DamageEffect._announce]).
		DamageEffect.announce_damage(ctx.event_bus, ctx.damage_credit(), victim, dealt)
		if dealt > 0 and victim.has_method("take_damage"):
			victim.take_damage(dealt)
		ctx.log_event({
			"effect": "damage",
			"target": victim,
			"amount": dealt,
			"category": category,
			"crit": false,
		})


## Extra RAW power this effect contributes beyond [member power] and the stat scaling.
## Zero, but DECLARED: [method DamageMath.is_damage_effect] duck-types damage effects on
## exactly this method, so having it is what lets the AI's planner and the shared power
## helper read this effect as a damaging one.
func bonus_power_for(_caster) -> int:
	return 0


## Is [param cell] TERRAIN the dash can pass over at all? Bounds and blocking terrain
## only. Deliberately says nothing about occupancy -- the walk handles units itself,
## because a dash passes through some of them. Anything a board cannot answer is
## permissive, exactly as the rest of the pipeline treats it.
func _can_enter(ctx: MoveContext, cell: Vector2i) -> bool:
	var board = ctx.board
	if board.has_method("in_bounds") and not bool(board.in_bounds(cell)):
		return false
	if board.has_method("is_blocked") and bool(board.is_blocked(cell)):
		return false
	return true


## Could the caster actually COME TO REST on [param cell]? Prefers the board's `can_fit`,
## which answers bounds + blocking terrain + other living units AND the caster's own
## FOOTPRINT in one call -- so a 2x2 unit is never squeezed into a 1-cell gap. The same
## primitive [method LeapEffect._can_land] prefers. Boards without it have already been
## asked everything they can answer by [method _can_enter] plus the walk's own occupancy
## check, so they pass.
func _can_land(ctx: MoveContext, cell: Vector2i) -> bool:
	var board = ctx.board
	if board.has_method("can_fit"):
		return bool(board.can_fit(ctx.caster, cell))
	return true


## True when EVERY unit in [param units] is hostile to the caster. False without the
## allegiance query, so a board that cannot answer never lets the dash pierce anything --
## it fails closed rather than inventing hostility.
func _all_enemies(ctx: MoveContext, units: Array) -> bool:
	var board = ctx.board
	if not board.has_method("are_enemies"):
		return false
	for unit in units:
		if not bool(board.are_enemies(ctx.caster, unit)):
			return false
	return true


func describe() -> String:
	if description_override != "":
		return description_override
	return "Dash through up to %d enemies, dealing %d %s damage to each" % [
		max_pierce, power, CombatTypes.DamageCategory.keys()[category].to_lower()]
