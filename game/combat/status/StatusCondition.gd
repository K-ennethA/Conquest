extends Resource
class_name StatusCondition

## A multi-turn condition on a unit (burn, poison, regen, timed buff, …).
##
## Built on the shared effect pipeline: a condition simply owns a list of
## [MoveEffect]s ([member tick_effects]) that fire once per turn while it is
## active. So a burn is a [StatusCondition] whose tick_effects = [DamageEffect];
## a regen is one whose tick_effects = [HealEffect]; a timed buff is one whose
## tick_effects = [] plus an [member on_apply] / [member on_expire] pair (or a
## StatModifierEffect applied by the inflicting move).
##
## Ticking is deterministic: [method tick] builds a minimal [MoveContext] with
## the affected unit as its own caster over a single cell, then applies each
## effect in order — the exact same resolution path a move uses.

## How a freshly applied copy interacts with an identical condition already on
## the unit (matched by [member id]).
enum Stacking {
	REFRESH,  ## reset the existing condition's remaining duration; no new instance
	STACK,    ## add an independent second instance (both tick)
	IGNORE,   ## keep the existing condition unchanged; drop the new one
}

@export var id: StringName = &""
@export var display_name: String = ""
## Turns the condition lasts. Must be > 0, or -1 for permanent (never expires).
@export var duration_turns: int = 1
## Effects applied to the affected unit once per [method tick].
@export var tick_effects: Array[MoveEffect] = []
@export var stacking: Stacking = Stacking.REFRESH

## Ceiling on how many independent instances of this condition may be live on one
## unit at once — its SEVERITY cap. Only [constant Stacking.STACK] can ever reach
## it (REFRESH and IGNORE never add a second instance), and once it is reached a
## further application refreshes the OLDEST live instance instead of deepening the
## severity: re-applying a maxed poison keeps it on the target but cannot make it
## worse. Enforced by [method StatusController.add_status].
##
## -1 (the default) means UNBOUNDED, which is precisely how STACK behaved before
## this field existed — so every status authored until now is unchanged. It is the
## default rather than 1 for that reason: 1 would have silently demoted every
## existing STACK condition to REFRESH.
@export var max_stacks: int = -1

## Standing rules the condition imposes while it is active, queried rather than
## applied — the status-side mirror of [member TileEffectResource.rule_flags].
## A tick effect MUTATES the unit; a rule flag simply says the unit's rules are
## different right now, e.g. [code]{ "immobilized": true }[/code] (cannot move).
## Merged across every active condition by
## [method StatusController.has_rule_flag]; empty (the default) is inert, so a
## condition authored before this existed behaves exactly as it always did.
@export var rule_flags: Dictionary = {}

## Multiplier this condition applies to damage its unit TAKES while active: 1.0
## (the default) is inert, below 1.0 is a reduction (0.6 = takes 40% less), above
## 1.0 a vulnerability. This is the STATUS-side mirror of the passive
## "damage_taken_scale" rule modifier a defender's ability can carry
## ([DamageEffect.damage_taken_scale_for]).
##
## AGGREGATION IS "TAKE THE STRONGEST", NOT "COMPOUND". If several DIFFERENT active
## statuses each carry a scale, [method StatusController.status_damage_taken_scale]
## returns the single most-protective one (the MINIMUM) -- never their product and
## never their sum. Two same-kind reductions must not amplify or deepen each other;
## a reduction status is authored as [constant Stacking.REFRESH] so re-applying it
## only refreshes its timer. Appended LAST so every status .tres authored before it
## reads back the inert 1.0 default.
@export var damage_taken_scale: float = 1.0

# --- Which turn boundaries count the duration down (CONQUEST.md rule 6a) ------
#
# A duration of N means one of two different things, and a single "count down at the
# afflicted unit's turn start" clock can only express one of them:
#
#   * PROTECTIVE -- "protect me through the opponents' phase(s)". A 1-turn guard cast on
#     your own turn covers the enemy's reply and is gone as your next turn opens. This
#     counts down at the unit's TURN START ([method StatusController.tick_all]) and is
#     the clock every status had before this field existed.
#   * AFFLICTION -- "you suffer this on your next N turns". A 1-turn Ensnared/Flinched
#     inflicted by a foe must stop the victim's NEXT turn, so it counts down at the
#     unit's TURN END ([method StatusController.tick_turn_end]), and only for a turn the
#     unit OPENED under it -- the turn it landed in never counts, so a debuff that lands
#     mid-turn (a trap sprung on your own move) still costs you a whole turn later.
#     Under the old start-of-turn clock a 1-turn debuff from an enemy expired at the very
#     tick that opened the victim's turn, i.e. it never mattered at all.
#
# Tick EFFECTS (poison damage, regen, entangled's slow) fire at the turn-start tick in
# BOTH clocks, and an affliction fires exactly as many ticks as its duration -- only the
# moment the condition LEAVES the unit moves (from turn start to that turn's end).

## Which turn boundary counts a live instance's duration down.
enum Clock {
	AUTO,        ## decided per application from who inflicted it -- see [method resolve_clock]
	PROTECTIVE,  ## counts at the afflicted unit's turn START (buffs, guards, fuses)
	AFFLICTION,  ## counts at the END of each turn the afflicted unit opened under it (debuffs, control)
}

## Authored clock. [constant Clock.AUTO] (the default, and what every .tres authored
## before this field reads back) derives it from the applier: a HOSTILE applier or the
## ENVIRONMENT (a tile) -> AFFLICTION; the unit itself, an ally, or nobody (a code-built
## reward, a restored save) -> PROTECTIVE. Author PROTECTIVE / AFFLICTION only when the
## timing is part of the status' CONTRACT whoever applies it (the Abyssal Maw fuse must
## erupt at its carrier's next turn START, so it pins PROTECTIVE).
@export var clock: Clock = Clock.AUTO

## Remaining turns for a live instance. Seeded from [member duration_turns] when
## the condition is added to a [StatusController]; -1 means permanent.
##
## What a "turn" is depends on [member counts_own_turns]: for an AFFLICTION it is the
## number of the unit's own turns still to be played under it, INCLUDING the one in
## progress; for a PROTECTIVE condition it is the number of the unit's turn starts still
## to pass before it lapses. Either way it is the number the UI shows ("1 turn").
var turns_left: int = 0

## The RESOLVED clock of this live instance: true = AFFLICTION (count at turn end),
## false = PROTECTIVE (count at turn start). Stamped by [method StatusController.add_status]
## (and re-stamped on every refresh) from [method resolve_clock]. Runtime state, so
## [method Resource.duplicate] never carries it onto a fresh copy.
var counts_own_turns: bool = false

## AFFLICTION bookkeeping: true from the turn-start tick that opens one of the unit's
## turns under this instance until that turn's END is counted. It is what makes "the turn
## it landed in never counts" true -- an instance applied mid-turn has not seen that turn
## open -- and it lets a turn start count a previous turn whose end beat never arrived, so
## a turn system that skips an end can delay an expiry by one turn but never strand one.
var own_turn_open: bool = false

## True when the ENVIRONMENT inflicted this instance (a tile effect: vine trap, rubble),
## rather than a unit. Tiles resolve with their occupant as the context's caster, so
## without this a trap's Ensnared would read as SELF-applied and take the protective
## clock. Stamped by [ApplyStatusEffect] from [member MoveContext.environmental]; runtime
## state, re-stated across the duplicate in [method StatusController.add_status].
var inflicted_by_environment: bool = false

# --- Who applied this (indirect kill attribution) -----------------------------
#
# A live instance remembers the unit that INFLICTED it, so the damage its ticks deal
# can be credited to that unit rather than to the victim. Without it a poison tick
# announced the victim as its own attacker and a death by poison credited nobody --
# no ON_KILL, no vampiric heal, no Reanimate.
#
# HELD WEAKLY, ON PURPOSE. A status routinely outlives its applier (a 3-turn poison
# on a board where the poisoner dies next turn), and a strong reference from a
# Resource to a freed Node is exactly the dangling-object crash this project cannot
# afford mid-turn. A freed applier resolves to null, which the attribution rule
# already reads as "credit nobody".
#
# NOT EXPORTED, so it is per-instance runtime state that [method Resource.duplicate]
# does not carry -- the same shape as [member turns_left] and
# [member StatModifierStatus._modifier_id]. Every place that duplicates a condition
# on its way onto a unit ([ApplyStatusEffect], [InfestEffect],
# [method StatusController.add_status]) therefore re-states the source explicitly,
# and the shared authoring .tres is never mutated.

## Weak handle on the applier; null when nothing applied it or it has been freed.
var _source_ref: WeakRef = null


## Record the unit that applied this instance. Null clears the attribution.
func set_source(unit) -> void:
	_source_ref = weakref(unit) if unit != null else null


## The unit that applied this instance, or null when there was none or it has been
## freed. Resolution is always through the weak handle -- never cache the result
## across turns.
func get_source():
	if _source_ref == null:
		return null
	var unit = _source_ref.get_ref()
	if unit == null or not is_instance_valid(unit):
		return null
	return unit


## Resolve this condition's clock for landing on [param target]: true = AFFLICTION
## (counts the target's own turn ENDS), false = PROTECTIVE (counts its turn STARTS).
## An authored [member clock] wins; [constant Clock.AUTO] asks
## [method is_affliction_from] with this instance's applier and environment stamp.
## Deterministic -- ownership and status flags only, no RNG, no signals.
func resolve_clock(target) -> bool:
	match clock:
		Clock.PROTECTIVE:
			return false
		Clock.AFFLICTION:
			return true
	return is_affliction_from(get_source(), target, inflicted_by_environment)


## THE AUTO RULE, shared by statuses and timed stat modifiers ([StatModifierEffect]) so
## the two can never disagree about what a "1-turn debuff" means.
##
## Something counts the target's OWN turns (AFFLICTION) when it was forced on the target
## from outside: by the environment, or by a unit HOSTILE to it -- a different owner, or
## a unit that is itself mind-controlled (a puppet striking its own side is acting for the
## enemy). It keeps the protective start-of-turn clock when the target applied it to
## itself, when an ally did, or when nobody did (code-built rewards, a restored save):
## those are the buffs whose "1 turn" has always meant "through the opponents' reply".
##
## Duck-typed and null-safe: a mock exposing no ownership is never hostile, so every
## fixture that predates the two clocks keeps the clock it always had.
static func is_affliction_from(source, target, from_environment: bool = false) -> bool:
	if from_environment:
		return true
	if source == null or target == null or source == target:
		return false
	if not is_instance_valid(source) or not is_instance_valid(target):
		return false
	if source.has_method("is_controlled") and bool(source.is_controlled()):
		return true
	var source_owner = _owner_of(source)
	var target_owner = _owner_of(target)
	if source_owner == null or target_owner == null:
		return false
	return source_owner != target_owner


## [param unit]'s owning player, read the way [method BoardAdapter._owner_of] reads it.
static func _owner_of(unit):
	if unit == null:
		return null
	if unit.has_method("get_owner_player"):
		return unit.get_owner_player()
	if "owner_player" in unit:
		return unit.get("owner_player")
	return null


## True while this live instance still has time on it (or is permanent).
func is_active() -> bool:
	return turns_left != 0


## True if this condition never expires on its own.
func is_permanent() -> bool:
	return duration_turns == -1


## Apply every tick effect to [param target] once, resolved through the shared
## effect pipeline. [param board] must expose the standard board interface
## (see [MoveContext]). Returns the accumulated event log for this tick.
func tick(target, board) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if target == null or board == null:
		return events
	var cell: Vector3i = Vector3i.ZERO
	if board.has_method("cell_of"):
		cell = board.cell_of(target)
	var ctx := MoveContext.new(target, board, _tick_move(), cell, [cell] as Array[Vector3i])
	# Floating combat text / battle log: name the status as the source ("Poisoned").
	ctx.source = CombatText.make_source(CombatText.SRC_STATUS, display_name if display_name != "" else String(id), id)
	# A tick is not a swing: it ALWAYS lands. Without this the shared damage pipeline
	# rolls the victim's evasion (terrain avoid included) against a poison it is already
	# carrying, on an unseeded per-tick RNG -- so a poisoned unit standing in tall grass
	# skipped ticks at random, and no two peers/replays agreed on which. See
	# [member MoveContext.guaranteed_hit].
	ctx.guaranteed_hit = true
	# INDIRECT KILL ATTRIBUTION. The context's CASTER stays the afflicted unit -- that is
	# what makes the SELF-targeted tick move gather exactly this unit, and what keeps the
	# tick's damage math byte-identical to before. Only the CREDIT is redirected, to the
	# unit that applied the condition (null when it is gone, or when the unit poisoned
	# itself). See [method DamageEffect.credited_source] for the rule.
	ctx.set_damage_credit(DamageEffect.credited_source(get_source(), target, board))
	for effect in tick_effects:
		if effect:
			effect.apply(ctx)
	for e in ctx.results:
		events.append(e)
	return events


## Hook fired when the condition is first added to a unit. Empty by default;
## override via subclass or extend later (e.g. an initial stat modifier).
func on_apply(_target, _board) -> void:
	pass


## Hook fired when the condition expires or is cleared. Empty by default.
func on_expire(_target, _board) -> void:
	pass


## Synthetic self-targeted move used to route tick effects through a
## [MoveContext]. SELF targeting makes [method MoveContext.gather_targets]
## return exactly the affected unit.
func _tick_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = id if id != &"" else &"status_tick"
	m.display_name = display_name
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.SELF
	pattern.min_range = 0
	pattern.max_range = 0
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	pattern.affects_caster_tile = true
	m.targeting = pattern
	return m
