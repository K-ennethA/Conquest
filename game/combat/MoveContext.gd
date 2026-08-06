extends RefCounted
class_name MoveContext

## Runtime state handed to each [MoveEffect] while a move resolves.
##
## Decouples effects from the concrete game: effects talk to [member board] and
## to units through small duck-typed interfaces, so the same effect works in the
## live game and against a mock board in tests.
##
## Expected [member board] interface (any object with these methods):
##   cell_of(unit) -> Vector2i
##   units_at(cell: Vector2i) -> Array
##   are_enemies(a, b) -> bool
##   are_allies(a, b) -> bool
##   set_tile(cell: Vector2i, tile_id) -> void
##   move_unit(unit, to_cell: Vector2i) -> void
##
## Expected unit interface: get_stat(name) -> int, take_damage(n), heal(n),
## add_stat_modifier(stat, amount, duration).

var caster                       ## the acting unit
var board                        ## board query/mutation adapter (see above)
var move: MoveResource
var aim_cell: Vector2i
var affected_cells: Array[Vector2i]
var results: Array[Dictionary] = []

## Optional event-bus override for effects that announce themselves (see
## [DamageEffect]). Left null in the live game, where those effects fall back to
## the [code]GameEvents[/code] autoload; tests inject a mock bus here.
var event_bus = null

## RNG for hit/crit rolls. Injected by [MoveExecutor] (seedable for deterministic
## replay / networked peers); a randomized one is created lazily if left null.
var rng: RandomNumberGenerator = null
## Per-target hit/crit resolution, cached so multiple effects on the same move
## share one roll per target (a miss misses everything, a crit crits everything).
var _hit_cache: Dictionary = {}


func _init(p_caster, p_board, p_move: MoveResource, p_aim: Vector2i, p_cells: Array[Vector2i]) -> void:
	caster = p_caster
	board = p_board
	move = p_move
	aim_cell = p_aim
	affected_cells = p_cells


func get_caster_stat(stat_name: String) -> int:
	if caster and caster.has_method("get_stat"):
		return caster.get_stat(stat_name)
	return 0


## Percent chance (0..100) this move lands on [param target]: move accuracy minus
## the target's evasion.
func hit_chance(target) -> float:
	if move == null:
		return 100.0
	# Terrain avoid (FE model): the tile under the defender adds to its evasion,
	# summed at combat time from the cell's passive tile effects.
	var evasion := float(_stat(target, "evasion")) + float(TerrainStats.bonus_for(target, "evasion", board))
	return clampf(move.accuracy * 100.0 - evasion, 0.0, 100.0)


## Percent chance (0..100) of a critical hit on [param target]: the move's base
## crit plus the caster's crit stat.
func crit_chance(_target) -> float:
	if move == null:
		return 0.0
	return clampf(move.crit_chance * 100.0 + float(get_caster_stat("crit")), 0.0, 100.0)


## When true this context NEVER rolls to hit: every target takes a guaranteed,
## non-critical hit and the generator is untouched.
##
## This is what a STATUS TICK resolves through ([method StatusCondition.tick]). Poison
## is not an attack you can dodge — it is already inside you — but a tick routed through
## the ordinary pipeline was rolling [method hit_chance] like any swing, so the victim's
## EVASION applied to it. Standing in tall grass (+15 terrain avoid) therefore gave a
## poisoned unit a 15% chance to dodge its own poison each turn, and because a tick's
## context carries no injected RNG that roll was made on an unseeded generator — so the
## same battle desynced between networked peers and replayed differently.
##
## Default false, so a move, a hazard and an ability all resolve exactly as before.
var guaranteed_hit: bool = false

# --- Damage CREDIT (indirect kill attribution) --------------------------------
#
# Damage normally belongs to [member caster]: the unit swinging is the unit credited.
# INDIRECT damage breaks that. A poison tick resolves with the VICTIM as its caster
# (that is what makes the SELF-targeted tick move gather exactly the poisoned unit),
# so announcing `caster` as the attacker made the victim credit ITSELF for its own
# death -- and nobody's ON_KILL fired on a damage-over-time kill.
#
# The fix is deliberately NOT "swap the caster": every stat lookup, passive modifier
# and target gather in the pipeline reads `caster`, and changing it would silently
# retune what a tick DEALS. Only the CREDIT moves. So the tick sets this override and
# the damage MATH is byte-identical to what it was.
#
# Three states, which is why a plain null is not enough:
#   * unset (the default)  -> credit the caster, exactly as always.
#   * set to a unit        -> credit that unit (the status' applier, a hazard's owner).
#   * set to null          -> credit NOBODY (a dead applier, or self-inflicted damage;
#                             see [method DamageEffect.credited_source]).

## The unit to credit instead of [member caster]; only meaningful while
## [member _damage_credit_set] is true.
var _damage_credit = null
## True once [method set_damage_credit] has spoken, so "credit nobody" (null) is
## distinguishable from "nobody said anything" (credit the caster).
var _damage_credit_set: bool = false


## Redirect credit for the damage this context deals. Pass null to credit NOBODY --
## that is a real answer, not an absence, and it is what a status applied by a unit
## that has since died reports.
func set_damage_credit(unit) -> void:
	_damage_credit = unit
	_damage_credit_set = true


## Who this context's damage is credited to: the override when one was set (possibly
## null = nobody), else [member caster]. Read by [method DamageEffect._announce].
func damage_credit():
	return _damage_credit if _damage_credit_set else caster


## Resolve (once, then cache) whether this move hits [param target] and whether it
## crits. Returns { hit, crit, hit_pct, crit_pct }.
func resolve_hit(target) -> Dictionary:
	if _hit_cache.has(target):
		return _hit_cache[target]
	if guaranteed_hit:
		var certain := { "hit": true, "crit": false, "hit_pct": 100.0, "crit_pct": 0.0 }
		_hit_cache[target] = certain
		return certain
	var hp := hit_chance(target)
	var cp := crit_chance(target)
	var r := _get_rng()
	var did_hit := r.randf() * 100.0 < hp
	var did_crit := did_hit and r.randf() * 100.0 < cp
	var out := { "hit": did_hit, "crit": did_crit, "hit_pct": hp, "crit_pct": cp }
	_hit_cache[target] = out
	return out


## One independent probability roll (0..1) against THIS context's RNG — the same
## generator [method resolve_hit] uses, so any effect built on it inherits the
## executor's seeding and stays deterministic for replays and networked peers.
##
## Certainties short-circuit WITHOUT touching the generator: an effect left at its
## default 1.0 chance consumes no roll, so adding a probability field to an
## existing effect cannot shift the RNG stream for anything resolved after it.
func roll(probability: float) -> bool:
	if probability >= 1.0:
		return true
	if probability <= 0.0:
		return false
	return _get_rng().randf() < probability


func _get_rng() -> RandomNumberGenerator:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng


func _stat(unit, stat_name: String) -> int:
	if unit and unit.has_method("get_stat"):
		return unit.get_stat(stat_name)
	return 0


## Units in the affected area that match the move's target kind.
func gather_targets() -> Array:
	var found: Array = []
	for cell in affected_cells:
		for unit in board.units_at(cell):
			if _matches_target_kind(unit) and unit not in found:
				found.append(unit)
	return found


func log_event(event: Dictionary) -> void:
	results.append(event)


func _matches_target_kind(unit) -> bool:
	# Resolved through the shared CombatTypes helper so an instant move's target
	# gathering and a TravelingHazard's per-band filter can never drift apart. TILE /
	# EMPTY_TILE fall through to the helper's default (false) -- those effects don't
	# gather units.
	#
	# CONTROL INVERSION: while the caster is mind-controlled, ENEMY and ALLY swap, so an
	# ENEMY-targeted move (the hijacked unit's own attack) actually LANDS on its allies
	# rather than gathering nobody. Gated on the caster reporting is_controlled(), so a
	# normal caster resolves exactly as before.
	# Mode-aware: a two-mode move (Prism Bulwark) targets SELF or ENEMY depending on the
	# caster's state, so gathering must read the pattern that is actually in force.
	var pattern: TargetingPattern = move.targeting_for(caster)
	if pattern == null:
		return false
	var kind: int = pattern.target_kind
	if caster != null and caster.has_method("is_controlled") and caster.is_controlled():
		kind = _invert_allegiance(kind)
	if not CombatTypes.unit_matches_target_kind(kind, caster, unit, board):
		return false
	# FOG OF WAR, AND THE ONE PLACE IT TOUCHES TARGETING. A unit the CASTER'S OWN SIDE cannot
	# see is not gathered, so a move aimed into the dark resolves against exactly what a move
	# aimed at empty ground resolves against: nothing.
	#
	# WHY HERE AND NOT IN THE AIM VALIDITY. Refusing the AIM at a hidden unit's cell would make
	# that cell behave differently from the empty ground it is supposed to look like -- the
	# player (or a script) could sweep the board with a legal/illegal probe and read off exactly
	# where the hidden units are. Fog that can be probed is not fog. Gathering nothing leaks
	# nothing, and it keeps every GROUND-targeted move castable anywhere in its range, which is
	# the rule: fog hides units, not terrain.
	#
	# WHY THE SUBMERGED PRECEDENT DOES NOT APPLY. SubmergedStatus deliberately does NOT filter
	# this path, because an untargetable flag here would also make a submerged unit unhealable
	# and unbuffable BY ITS OWN SIDE. Vision cannot do that: a side always sees its own units
	# (VisionSystem.is_unit_visible short-circuits on ownership), so a heal or a buff can never
	# be blocked by this line -- only a reach into somebody else's dark.
	#
	# LOCKSTEP-SAFE with no network code: `caster` is the unit the command names, identical on
	# every peer, so every peer resolves this gather through the SAME side's vision over the
	# same board and reaches the same targets. And with fog off (every map that predates it)
	# gatherable() returns true unconditionally, so this line is the identity function and the
	# gather is byte-for-byte what it always was.
	return VisionSystem.gatherable(caster, unit)


## Swap ENEMY <-> ALLY, leaving SELF / ANY_UNIT / tile kinds untouched. The one place
## the control allegiance flip is spelled for target gathering.
func _invert_allegiance(kind: int) -> int:
	if kind == CombatTypes.TargetKind.ENEMY:
		return CombatTypes.TargetKind.ALLY
	if kind == CombatTypes.TargetKind.ALLY:
		return CombatTypes.TargetKind.ENEMY
	return kind
