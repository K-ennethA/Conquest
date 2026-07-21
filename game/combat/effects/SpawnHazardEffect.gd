extends MoveEffect
class_name SpawnHazardEffect

## Casts a persistent, crawling [TravelingHazard] down a cardinal lane. Unlike
## [DamageEffect], which hits the aim area instantly, this spawns a vine that
## ADVANCES over several turns, damaging what it enters as it goes -- an anchored
## boss's answer to being kited.
##
## The move's [TargetingPattern] only picks the AIM (direction + distance); the
## lane geometry is derived here from the caster->aim heading, reusing
## [method TargetingPattern._cardinal_dir] so a diagonal aim collapses to the same
## clean face LINE/ARC use. The FIRST segment resolves immediately on cast (so the
## cast turn deals damage); the live [HazardManager] crawls the rest.

## Raw damage per hit before the caster stat is folded in.
@export var power: int = 12
## Caster stat added to power (e.g. "attack"). Empty = flat power.
@export var scaling_stat: String = "attack"
## Fraction of the scaling stat added to power.
@export var scale: float = 0.5
@export var category: CombatTypes.DamageCategory = CombatTypes.DamageCategory.PHYSICAL

## Who the crawling band damages, relative to the CASTER. ENEMY (the safe default)
## makes a generic hazard hit only the caster's foes; ANY_UNIT makes it
## indiscriminate (Forest Barrage); ALLY could drive a friendly effect. Evaluated
## through the same [enum CombatTypes.TargetKind] instant moves use.
@export var affiliation: CombatTypes.TargetKind = CombatTypes.TargetKind.ENEMY

## Lane width in cells (perpendicular to travel). Odd values center on the aim line;
## 5 -> a band spanning flank offsets -2..+2.
@export var width: int = 5
## Rows the vine advances per tick.
@export var speed: int = 2
## Total forward rows the vine travels before expiring.
@export var travel_range: int = 6


func apply(ctx: MoveContext) -> void:
	if ctx == null or ctx.board == null or not ctx.board.has_method("cell_of"):
		return
	var board = ctx.board
	var origin: Vector2i = board.cell_of(ctx.caster)
	# Same heading rule as LINE/ARC so the lane's diagonal behaviour matches them.
	var facing := TargetingPattern._cardinal_dir(origin, ctx.aim_cell)

	# Snapshot the raw damage from the caster's CURRENT stats, so a later boss
	# buff/debuff cannot retroactively retune an already-airborne vine.
	var bonus: int = 0
	if scaling_stat != "":
		bonus = int(round(float(ctx.get_caster_stat(scaling_stat)) * scale))
	var raw: int = power + bonus

	var half_width: int = maxi(0, (width - 1) / 2)
	var hazard := TravelingHazard.new(origin, facing, half_width, speed, travel_range,
		raw, category, affiliation, ctx.caster)

	# Resolve the FIRST segment immediately so the cast turn itself deals damage.
	var first: Dictionary = hazard.advance(board)
	_log_segment(ctx, first)

	# Hand the vine to the live HazardManager via the loosest coupling that stays
	# headless-testable: a GameEvents signal it listens for. No hard dependency on a
	# live manager; degrades to a no-op when nothing is connected.
	_dispatch(ctx, hazard, first)


## Emit the spawn request (and telegraph the cast band) on the injected event bus
## when there is one -- tests inject a mock via [member MoveContext.event_bus] --
## else the GameEvents autoload, mirroring [method DamageEffect._announce].
func _dispatch(ctx: MoveContext, hazard, first_result: Dictionary) -> void:
	var bus = ctx.event_bus
	if bus == null:
		bus = GameEvents
	if bus == null:
		return
	if bus.has_signal(&"hazard_spawn_requested"):
		bus.emit_signal(&"hazard_spawn_requested", hazard)
	if bus.has_signal(&"hazard_advanced"):
		var total: int = 0
		for d in first_result.get("damaged", []):
			total += int(d.get("amount", 0))
		bus.emit_signal(&"hazard_advanced", hazard,
			first_result.get("cells", []), first_result.get("next_cells", []), total)


## Log the cast segment's hits into the move's result stream, mirroring
## [DamageEffect]'s damage events so the combat log / forecast can read them.
func _log_segment(ctx: MoveContext, result: Dictionary) -> void:
	for d in result.get("damaged", []):
		ctx.log_event({
			"effect": "hazard",
			"target": d.get("unit"),
			"amount": int(d.get("amount", 0)),
			"category": category,
		})


func describe() -> String:
	if description_override != "":
		return description_override
	return "Erupt a %d-wide vine that crawls %d cells, dealing %d %s damage to all it enters" % [
		width, travel_range, power, CombatTypes.DamageCategory.keys()[category].to_lower()]
