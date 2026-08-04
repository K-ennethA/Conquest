extends Resource
class_name TileEffectResource

## A data-driven behaviour that a tile imposes on the unit standing on it.
##
## Built on the shared effect pipeline: a tile effect simply owns a list of
## [MoveEffect]s that fire when its [member trigger] occurs — exactly the same
## resolution path a move or a [StatusCondition] uses. So authoring a burning,
## empowering, fortifying, or hiding tile is data, not code: fire is a
## [TileEffectResource] whose effects = [DamageEffect]; empowering water is one
## whose effects = [StatModifierEffect] gated by a [member required_unit_tag].
##
## Effects are resolved through a minimal SELF-targeted [MoveContext] built over
## the occupant's own cell (see [method run]), mirroring [method
## StatusCondition.tick]. State that isn't a mutation — stealth, fortification —
## is expressed as [member rule_flags] so other systems (e.g. targeting) can
## query it without anything being applied.
##
## ELEMENT. A tile effect HAS one, and it is not stored here: it is looked up by
## [member id] in [member ElementChartResource.tile_elements], the single authority for
## every element number in the game (CONQUEST.md rule 9). See [method element]. Two
## things follow from it, both data-driven and both deterministic:
##
##   * DAMAGE the tile deals is scaled by the matchup, tile element vs occupant element
##     — a nature unit resists nature brambles. Carried by stamping the synthetic move
##     with [method ElementChart.mark_environment] in [method _self_move], so the damage
##     rides the ordinary [DamageMath] chain and preview cannot drift from the tick.
##   * WHAT THE TILE GIVES OR TAKES (an evasion bonus, a heal, a stat penalty) is
##     modulated for an occupant of the tile's OWN element by
##     [method ElementChart.home_effect_amount] — see [method run].
##
## A STATUS the tile applies is deliberately untouched (see that method's note), and so
## is [member move_cost_bonus]: an element cannot make stone cheaper to walk over.
##
## STANDING vs STEPPING. Every effect here is a STANDING effect by default: an ON_ENTER
## effect fires for the cell a unit LANDS on and pass-through is free. [member
## springs_on_pass] is the authored opt-out that makes an effect a TRAP -- it springs on a
## unit that merely crosses the cell -- and [member halts_movement] additionally stops the
## move dead on it. Nothing infers trap-ness from an effect's payload; a designer ticks the
## box (CONQUEST.md rule 10).

## When the effect fires for an occupying unit.
enum Trigger {
	ON_ENTER,                       ## once, when a unit steps onto the tile
	ON_TURN_START_WHILE_OCCUPYING,  ## each turn start the unit is still on it
	ON_EXIT,                        ## once, when a unit leaves the tile
	PASSIVE_WHILE_OCCUPYING,        ## a standing state, not a per-event mutation
}

## Which occupants the effect is allowed to touch. Perspective for the ENEMIES /
## ALLIES variants is a reference unit the board supplies via a duck-typed
## [code]perspective_unit()[/code]; without one, those variants match nobody.
enum AffectedFactions {
	ALL,               ## any occupant
	OCCUPANT_ENEMIES,  ## occupants hostile to the tile/board perspective
	OCCUPANT_ALLIES,   ## occupants friendly to the tile/board perspective
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var trigger: Trigger = Trigger.ON_ENTER
@export var affected_factions: AffectedFactions = AffectedFactions.ALL

## Empty = affects any unit. Otherwise only affects a unit that reports the tag,
## either via a duck-typed [code]has_tag(tag)[/code] method or a [code]tags[/code]
## array property. This is how "water empowers only aquatic units" is authored.
@export var required_unit_tag: StringName = &""

## Effects applied to the occupant when the trigger fires, in order.
@export var effects: Array[MoveEffect] = []

## Extra MOVEMENT COST to enter this cell, on top of the base terrain cost, for any unit
## the effect [method applies_to] (so an enemies-only rubble field slows foes crossing it
## but not the placer's own side). Read by [MovementResolver] when it floods reachable
## cells, so the penalty bites on the SAME turn a unit tries to cross -- unlike an ON_ENTER
## status, which only lands after the step and only if the unit STOPS on the cell. 0 = none.
@export var move_cost_bonus: int = 0

## PASS-THROUGH TRAP: when true, this effect springs on a unit that merely WALKS OVER the
## cell, not only on one that STOPS there. This is THE one-rule distinction in the game's
## terrain model (CONQUEST.md rule 10): a glowing tile hurts where you STAND, a TRAP springs
## where you STEP. It is AUTHORED, never inferred -- an ON_ENTER effect stays a landing-only
## effect unless a designer ticks this box, so rubble still only slows a unit that stops on
## it while Petalfang's Vine Trap catches anyone crossing the cell.
##
## Only meaningful on [constant Trigger.ON_ENTER]: the other triggers are about occupying a
## cell, which pass-through by definition is not.
@export var springs_on_pass: bool = false

## HALTS THE MOVE: when true, a unit that springs this trap mid-path STOPS on the trap cell --
## the rest of its move is cancelled and the trap cell becomes its landing cell (so the
## cell's ordinary ON_ENTER effects, this one included, resolve there exactly as if it had
## been the destination all along).
##
## Deliberately SEPARATE from [member springs_on_pass]: a trap that springs without halting
## (an alarm, a spore cloud) fires as the unit crosses and the move continues to its
## authored destination. Meaningless on its own -- a trap that does not spring on pass never
## gets the chance to halt anything.
@export var halts_movement: bool = false

## SINGLE-USE: when true, this effect is EXTINGUISHED (removed from the cell) the moment
## it actually fires on a unit -- a snare that springs once (Petalfang's Vine Trap) rather
## than a lasting field. Only removes the RUNTIME-placed copy; map-authored terrain is
## never removed (a lava tile stays lava). Contrast a timed field (e.g. a burn a move
## leaves for a few turns): that would persist and expire on its own, not on first contact.
@export var consume_on_trigger: bool = false

## RUNTIME owner of a PLACED effect (a trap laid by a unit), stamped by
## ApplyTileEffect at cast time; null for map-authored terrain. When set, the
## OCCUPANT_ENEMIES / OCCUPANT_ALLIES faction check is resolved against THIS owner
## (via the occupant's own get_owner_player) instead of the board perspective -- so a
## trap only springs on its placer's enemies and spares the placer's own side. Not
## exported: it is set live, per placement.
var owner_player = null

## Passive states that are queried rather than applied, e.g.
## [code]{ "untargetable": true }[/code] (stealth) or
## [code]{ "fortified": true }[/code]. Merged by [method TileEffectSystem.passive_flags].
@export var rule_flags: Dictionary = {}


## The one line a TRAP has to say for itself, shared by every surface that describes a
## tile: the in-battle [TerrainInfoPanel] row and the compendium's tile gallery both read
## THIS rather than writing their own wording, so "what a trap is" is data on the resource
## (CONQUEST.md rule 10) and renaming the rule is a one-line content edit.
##
## Empty string for everything that is not a pass-through trap, which is the answer a
## caller shows nothing for.
const TRAP_DESCRIPTOR := "Trap - springs when stepped on"


## [constant TRAP_DESCRIPTOR] when this effect is a pass-through trap, else [code]""[/code].
func trap_descriptor() -> String:
	return TRAP_DESCRIPTOR if is_pass_trap() else ""


## True when this effect is a PASS-THROUGH TRAP at all -- authored [member springs_on_pass]
## on an ON_ENTER effect. Everything that reasons about traps (the movement walk, the AI's
## avoidance, the preview warning, the terrain panel) asks THIS rather than reading the flag
## raw, so the "only ON_ENTER can spring" rule lives in exactly one place.
func is_pass_trap() -> bool:
	return springs_on_pass and trigger == Trigger.ON_ENTER


## True when this effect is a pass-trap that is ARMED AGAINST [param unit] right now -- i.e.
## walking over the cell would actually spring it. Combines [method is_pass_trap] with the
## ordinary faction / tag filter, so a placer's own side crosses its own trap for free.
func springs_on_pass_for(unit, board) -> bool:
	return is_pass_trap() and applies_to(unit, board)


## True if this effect is allowed to act on [param unit] right now — combines the
## faction filter and the [member required_unit_tag] filter.
func applies_to(unit, board) -> bool:
	if unit == null:
		return false
	if not _faction_ok(unit, board):
		return false
	if not _tag_ok(unit):
		return false
	return true


## This tile effect's ELEMENT, or &"" when nobody has elemented it.
##
## Read from the chart resource by [member id] — [ElementChartResource.tile_elements] is
## the authority, never a field on this resource (see the class note). An unelemented
## effect behaves in every respect as it did before elements reached tiles.
func element() -> StringName:
	return ElementChart.tile_element_of(self)


## Apply every effect to [param unit] once, resolved through a SELF-targeted
## [MoveContext] over the unit's cell (the same pipeline a move uses). Does NOT
## re-check [method applies_to] — callers filter first. Returns the event log.
##
## AT-HOME MODULATION: an effect carrying an authored MAGNITUDE (an [code]amount[/code],
## i.e. [StatModifierEffect] / [HealEffect] / [ShieldEffect]) is re-scaled for an
## occupant of this tile's own element, through [method ElementChart.home_effect_amount].
## The re-scaled effect is a DUPLICATE — these resources are loaded once and handed to
## every cell on the map, so mutating one in place would retune the terrain for everybody
## (CONQUEST.md rule 7). When the scale changes nothing (no element, no match, an effect
## with no magnitude) the authored resource is used untouched and nothing is allocated.
func run(unit, board) -> Array:
	var events: Array = []
	if unit == null or board == null:
		return events
	var cell: Vector2i = Vector2i.ZERO
	if board.has_method("cell_of"):
		cell = board.cell_of(unit)
	var ctx := MoveContext.new(unit, board, _self_move(), cell, [cell] as Array[Vector2i])
	# THE GROUND IS NOT A SWING YOU CAN DODGE. Exactly the rule a STATUS TICK follows
	# ([method StatusCondition.tick]) and for exactly the same reason: routed through the
	# ordinary pipeline, a tile effect rolled [method MoveContext.hit_chance] against the
	# occupant -- and TERRAIN AVOID feeds that roll, so a unit standing on a cell that is
	# BOTH tall grass (+15 avoid) and on fire got a 15% chance to dodge the fire it is
	# standing in. Worse, a tile context carries no injected RNG, so that roll came off an
	# unseeded generator and no two peers/replays agreed on which turns burned.
	#
	# Environmental damage LANDS. No roll, no crit, and (because guaranteed_hit
	# short-circuits ahead of [method MoveContext._get_rng]) no draw from any generator at
	# all -- which is what keeps a tile tick out of the lockstep RNG stream entirely.
	# The sibling rule for a crawling hazard is [method DamageEffect.resolve_hazard_damage],
	# which has never rolled either.
	ctx.guaranteed_hit = true
	for effect in effects:
		if effect:
			_at_home(effect, unit).apply(ctx)
	for e in ctx.results:
		events.append(e)
	return events


## [param effect] as it lands on [param unit] — the authored resource itself, or a
## duplicate whose magnitude has been re-scaled by this tile's element vs the unit's.
##
## Duck-typed on an integer [code]amount[/code], which is exactly the set of effects that
## express "how much": a buff, a debuff, a heal, a shield. [DamageEffect] carries
## [code]power[/code] instead and is deliberately NOT caught here — tile damage is scaled
## by the MATCHUP, one step later, inside [DamageMath].
func _at_home(effect, unit):
	var amount = effect.get("amount")
	if not (amount is int):
		return effect
	var scaled: int = ElementChart.home_effect_amount(self, int(amount), unit)
	if scaled == int(amount):
		return effect
	var copy = effect.duplicate()
	copy.set("amount", scaled)
	return copy


## What this tile effect's NON-DAMAGE payload does for [param unit], and what it would
## have done for anyone else:
##
##   authored -- int, the magnitude as authored (0 when the effect carries none)
##   landed   -- int, the magnitude after [method ElementChart.home_effect_amount]
##   kind     -- &"heal" / &"stat" / &"" , what the magnitude IS
##
## The first magnitude-bearing effect wins, in the effect's own authored order — the same
## first-in-order rule the cell's element badge uses, so both are deterministic and both
## point at the same thing.
##
## THE SAME FUNCTION THE RUN APPLIES. [method run] scales through
## [method ElementChart.home_effect_amount] and so does this, so a panel that says the
## meadow heals a nature unit for 13 is quoting the heal that unit is about to receive
## rather than modelling it (CONQUEST.md rule 9). `landed == authored` is the "the element
## rule changed nothing here" answer, which is what a UI checks to decide to say nothing.
func home_summary_for(unit) -> Dictionary:
	var out := { "authored": 0, "landed": 0, "kind": &"" }
	for effect in effects:
		if effect == null:
			continue
		var amount = effect.get("amount")
		if not (amount is int) or int(amount) == 0:
			continue
		out["authored"] = int(amount)
		out["landed"] = ElementChart.home_effect_amount(self, int(amount), unit)
		out["kind"] = &"heal" if effect is HealEffect else &"stat"
		return out
	return out


## What this tile effect's DAMAGE would take off [param unit] on its next tick — the
## element-adjusted number, from the same arithmetic the tick itself runs.
##
## 0 for a tile that deals no damage. Preview == reality by construction (CONQUEST.md
## rule 9): [method DamageEffect.apply] computes raw power, mitigates it, and hands it to
## [method DamageMath.apply_scales] with this same environment-marked synthetic move —
## which is line for line what this does. It is the terrain panel's readout, so what the
## card promises is what the tile takes off.
##
## THERE IS NO HIT CHANCE TO MODEL. This path deliberately contains no accuracy/evasion
## term, and since [method run] marks its context [member MoveContext.guaranteed_hit] the
## tick contains none either -- so this is not "damage on landing, chance shown elsewhere",
## it is the number the next tick takes off, full stop. Do not add a chance term to either
## side: they are equal by construction and a forecast that modelled a dodge the tick
## cannot perform would be the drift rule 9 exists to forbid.
func damage_preview_for(unit, board) -> int:
	if unit == null:
		return 0
	var synthetic := _self_move()
	var total: int = 0
	for effect in effects:
		if not DamageMath.is_damage_effect(effect):
			continue
		var mitigated: int = DamageMath.mitigate(
			DamageMath.raw_power(effect, unit), unit, effect.get("category"))
		total += int(DamageMath.apply_scales(mitigated, unit, unit, synthetic, board)["total"])
	return total


func _faction_ok(unit, board) -> bool:
	match affected_factions:
		AffectedFactions.OCCUPANT_ENEMIES:
			# A PLACED trap knows its owner: only its owner's ENEMIES spring it. A unit
			# with no owner (or the placer's own side) is spared.
			if owner_player != null:
				var occ = _unit_owner(unit)
				return occ != null and occ != owner_player
			var ref = _perspective(board)
			return ref != null and board.has_method("are_enemies") and board.are_enemies(ref, unit)
		AffectedFactions.OCCUPANT_ALLIES:
			if owner_player != null:
				return _unit_owner(unit) == owner_player
			var ref = _perspective(board)
			return ref != null and board.has_method("are_allies") and board.are_allies(ref, unit)
		_:  # ALL
			return true


## The owning Player of [param unit], or null (duck-typed for mocks).
static func _unit_owner(unit):
	if unit != null and unit.has_method("get_owner_player"):
		return unit.get_owner_player()
	return null


func _tag_ok(unit) -> bool:
	if required_unit_tag == &"":
		return true
	return _unit_has_tag(unit, required_unit_tag)


static func _perspective(board):
	if board and board.has_method("perspective_unit"):
		return board.perspective_unit()
	return null


## Duck-typed tag check: prefer a [code]has_tag()[/code] method, else read a
## [code]tags[/code] array property.
static func _unit_has_tag(unit, tag: StringName) -> bool:
	if unit == null:
		return false
	if unit.has_method("has_tag"):
		return unit.has_tag(tag)
	var tags = unit.get("tags")
	if tags is Array:
		for t in tags:
			if StringName(t) == tag:
				return true
	return false


## Synthetic self-targeted move used to route effects through a [MoveContext].
## SELF targeting makes [method MoveContext.gather_targets] return exactly the
## occupying unit.
##
## STAMPED WITH THIS TILE'S ELEMENT as an ENVIRONMENTAL source. That single mark is what
## makes tile damage elemented at all: [method DamageMath.apply_scales] already asks
## [method ElementChart.damage_scale_for] for every hit, and the mark tells that function
## the damage came FROM the ground rather than from a move landing on it — so the matchup
## applies and the tile amplifier / home benefit (which would both be double-counting the
## same fact) do not. No new pipeline, no second implementation of the chain.
func _self_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = id if id != &"" else &"tile_effect"
	m.display_name = display_name
	ElementChart.mark_environment(m, element())
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.SELF
	pattern.min_range = 0
	pattern.max_range = 0
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	pattern.affects_caster_tile = true
	m.targeting = pattern
	return m
