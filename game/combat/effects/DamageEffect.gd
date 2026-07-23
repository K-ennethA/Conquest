extends MoveEffect
class_name DamageEffect

## Deals damage to every valid target in the area, scaled by a caster stat and
## mitigated by the defender's matching defense stat.

@export var power: int = 20
## Caster stat added to power (e.g. "attack" or "magic"). Empty = flat power.
@export var scaling_stat: String = "attack"
## Fraction of the scaling stat added to power.
@export var scale: float = 1.0
@export var category: CombatTypes.DamageCategory = CombatTypes.DamageCategory.PHYSICAL

## Fraction (0..1) of the TOTAL damage this cast deals that heals the CASTER after
## resolution. 0.0 (the default) is a no-op, so every DamageEffect authored before
## this field is regression-safe. Reusable by any move (Siphon Bite drains half of
## what it deals). Healing is routed through the caster's own heal path, exactly
## like [HealEffect], and floored to whole HP via round().
@export_range(0.0, 1.0, 0.01) var lifesteal: float = 0.0

## --- Escalating group-crit (Splinter Volley's piercing bow) -----------------
##
## Normally each target rolls its OWN crit inside [method MoveContext.resolve_hit].
## When this is > 0 the WHOLE cast instead rolls crit ONCE as a group: the more
## targets the shot pierces, the higher the shared crit chance, and if it lands
## EVERY target in the area takes crit damage. Fully data-driven — no move needs
## bespoke code — and it reuses this effect's ENTIRE damage path; only the crit
## DECISION is swapped, never the damage math.
##
## Group crit chance = move.crit_chance + caster "crit" stat / 100 + this * (N-1),
## where N is the number of gathered targets. 0.0 (the default) keeps the historical
## per-target crit, so every DamageEffect authored before this field is unchanged.
## The forecast ([method MoveExecutor.preview_vs]) never rolls crit and never reads
## this field, so it is inherently preview-safe.
@export_range(0.0, 1.0, 0.01) var group_crit_bonus_per_extra_target: float = 0.0


func apply(ctx: MoveContext) -> void:
	var bonus := 0
	if scaling_stat != "":
		bonus = int(round(ctx.get_caster_stat(scaling_stat) * scale))
	var raw := power + bonus

	# Running total of HP actually removed this cast, so lifesteal can heal a fixed
	# fraction of it once all targets are resolved.
	var total_dealt: int = 0

	# Gather once: the target set drives both the loop and (for the piercing bow) the
	# escalating group-crit count, so they cannot disagree.
	var targets: Array = ctx.gather_targets()

	# Escalating group-crit: one shared crit roll for the entire cast, scaling with the
	# number of targets pierced. A no-op unless the move authors a per-target bonus, in
	# which case it REPLACES the per-target crit decision below for every target.
	var group_crit_scales: bool = group_crit_bonus_per_extra_target > 0.0
	var group_crit: bool = false
	if group_crit_scales:
		group_crit = _roll_group_crit(ctx, targets.size())

	for target in targets:
		var outcome := ctx.resolve_hit(target)
		if not outcome.get("hit", true):
			ctx.log_event({
				"effect": "damage",
				"target": target,
				"amount": 0,
				"category": category,
				"missed": true,
			})
			continue
		# Invulnerability short-circuits the ENTIRE damage pipeline, ahead of
		# mitigation, both scaling steps and crit. It is not "very high defense" --
		# it is a hard zero, and every later step has a maxi(1, ...) floor that would
		# otherwise drag it back up to 1. Logged explicitly so the combat log can say
		# the hit was NEGATED rather than silently reporting a 0 that reads like a bug.
		if is_invulnerable(target):
			_announce(ctx, target, 0)
			ctx.log_event({
				"effect": "damage",
				"target": target,
				"amount": 0,
				"category": category,
				"crit": false,
				"negated": true,
			})
			continue
		var dealt := _mitigate(raw, target)
		# --- Damage order, after mitigation ---------------------------------
		# 1. Predation bonus: a caster whose passives declare "damage_vs_restricted"
		#    hits harder into a target that cannot get away.
		# 2. Defender's own "damage_taken_scale" (Eldroot's Grovebound).
		# 3. Crit.
		# Attacker's bonus is applied BEFORE the defender's reduction so the two are
		# commutative multipliers on the mitigated number and neither one silently
		# dominates; crit stays LAST so it multiplies whatever actually got through,
		# which is what the forecast's crit_damage column claims it does.
		var restricted_scale: float = _restricted_scale(ctx, target)
		if restricted_scale > 1.0:
			dealt = maxi(1, int(round(float(dealt) * restricted_scale)))
		# 1b. Element-hunter bonus: a caster whose passives declare
		#     "damage_vs_element_<elem>" hits harder into a target of that element
		#     (Vineweave's Grass Cutter vs nature). Attacker-side, same shape as the
		#     predation bonus above, applied before the defender's reduction.
		var element_bonus: float = _element_bonus_scale(ctx, target)
		if element_bonus > 1.0:
			dealt = maxi(1, int(round(float(dealt) * element_bonus)))
		var taken_scale: float = damage_taken_scale_for(target, ctx.board)
		if not is_equal_approx(taken_scale, 1.0):
			dealt = maxi(1, int(round(float(dealt) * taken_scale)))
		# 4. TYPE MATCHUP: move-element vs target-type effectiveness, folded with the
		#    tile amplifier (target on a matching-element tile) and the target's own-
		#    element tile benefit. Resolved through the same shared helper the forecast
		#    uses so preview and hit cannot drift; a no-op (1.0) when neither the move
		#    nor the target carries an element, so unelemented content is unchanged.
		var element_scale: float = ElementChart.damage_scale_for(ctx.move, target, ctx.board)
		if not is_equal_approx(element_scale, 1.0):
			dealt = maxi(1, int(round(float(dealt) * element_scale)))
		var crit: bool = outcome.get("crit", false)
		# The escalating bow overrides the per-target crit with the single group roll:
		# the shot either crits every pierced target or none of them.
		if group_crit_scales:
			crit = group_crit
		if crit:
			dealt = maxi(1, int(round(dealt * CombatTypes.CRIT_MULTIPLIER)))
		if target.has_method("take_damage"):
			target.take_damage(dealt)
		total_dealt += dealt
		_announce(ctx, target, dealt)
		ctx.log_event({
			"effect": "damage",
			"target": target,
			"amount": dealt,
			"category": category,
			"crit": crit,
		})

	# Lifesteal: heal the caster for a fraction of everything this cast dealt. A no-op
	# at the default 0.0 (never touches the caster or the log), so it cannot perturb
	# any move that does not author it.
	if lifesteal > 0.0 and total_dealt > 0 and ctx.caster != null and ctx.caster.has_method("heal"):
		var healed: int = int(round(float(total_dealt) * lifesteal))
		if healed > 0:
			ctx.caster.heal(healed)
			ctx.log_event({
				"effect": "lifesteal",
				"target": ctx.caster,
				"amount": healed,
			})


## One shared crit roll for the escalating-bow path. The chance climbs with
## [param count] (the number of targets the shot pierces) and is rolled through the
## context RNG, so it is seeded/deterministic exactly like [method MoveContext.resolve_hit]'s
## per-target crit. A single target (count 1) rolls the move's base crit only.
func _roll_group_crit(ctx: MoveContext, count: int) -> bool:
	var chance: float = 0.0
	if ctx.move != null:
		chance = ctx.move.crit_chance
	chance += float(ctx.get_caster_stat("crit")) / 100.0
	chance += group_crit_bonus_per_extra_target * float(maxi(0, count - 1))
	return ctx.roll(clampf(chance, 0.0, 1.0))


func describe() -> String:
	if description_override != "":
		return description_override
	return "Deal %d %s damage" % [power, CombatTypes.DamageCategory.keys()[category].to_lower()]


## Announce one landed hit on the game-wide bus as
## [code]damage_dealt(attacker, defender, damage)[/code].
##
## This is the single emit point for that signal, and it is what finally lights up
## everything already listening for it — the hit flash and the attack/hit clips in
## [UnitAnimator], and the ON_ATTACK / ON_DAMAGED ability triggers routed by
## [AbilitySystem].
##
## Routed through [member MoveContext.event_bus] when a bus is injected, else the
## [code]GameEvents[/code] autoload. Guarded end to end so a headless or mocked
## context never errors: no bus, no such signal, or non-[Unit] participants (the
## autoload's signal is typed, so mocks must not reach it) all simply no-op.
static func _announce(ctx: MoveContext, target, dealt: int) -> void:
	if ctx == null or target == null:
		return
	var bus = ctx.event_bus
	if bus == null:
		if not (ctx.caster is Unit and target is Unit):
			return
		bus = GameEvents
	if bus == null or not bus.has_signal(&"damage_dealt"):
		return
	bus.emit_signal(&"damage_dealt", ctx.caster, target, dealt)


# --- Damage vs movement-restricted targets ----------------------------------
#
# Routed entirely through the EXISTING passive-modifier mechanism rather than a
# bespoke path: a PASSIVE AbilityResource contributes
# `rule_modifiers = { "damage_vs_restricted": 0.5 }` (= +50%), AbilitySystem
# merges it exactly like "extra_actions"/"extra_movement", and this effect reads
# the merged value. Null-safe end to end -- no ability system, no statuses, no
# board, or a mock unit missing any of the accessors all resolve to plain damage.


## Multiplier to apply to one hit: 1.0 normally, or 1.0 + the caster's merged
## "damage_vs_restricted" modifier when the TARGET is movement-restricted.
static func _restricted_scale(ctx: MoveContext, target) -> float:
	if ctx == null:
		return 1.0
	return restricted_scale_for(ctx.caster, target, ctx.board)


## Same predation multiplier, addressed by CASTER/TARGET rather than a MoveContext.
##
## This is the shared entry point so the combat FORECAST and the actual resolution
## can never disagree: MoveExecutor.preview_vs has no MoveContext (it deliberately
## rolls nothing), and duplicating the rule there would drift the moment either
## side was retuned. The bonus is fully deterministic -- it depends only on the
## target's current state -- so previewing it reveals nothing a player could game,
## unlike crit, which the forecast reports as a PROBABILITY and never rolls.
static func restricted_scale_for(caster, target, board = null) -> float:
	if caster == null or target == null:
		return 1.0
	if not _is_movement_restricted(target):
		return 1.0
	var bonus: float = _restricted_modifier_of(caster, board)
	if bonus <= 0.0:
		return 1.0
	return 1.0 + bonus


## The caster's merged "damage_vs_restricted" rule modifier (0.0 when it has no
## ability system, or no in-force passive that declares one).
static func _caster_restricted_modifier(ctx: MoveContext) -> float:
	if ctx == null:
		return 0.0
	return _restricted_modifier_of(ctx.caster, ctx.board)


## The caster's merged "damage_vs_restricted" rule modifier, addressed directly.
static func _restricted_modifier_of(caster, board) -> float:
	if caster == null:
		return 0.0
	# A live Unit exposes its component; a test mock may BE the ability system.
	var system = null
	if caster.has_method("get_ability_system"):
		system = caster.get_ability_system()
	elif caster.has_method("passive_modifiers"):
		system = caster
	if system == null or not system.has_method("passive_modifiers"):
		return 0.0
	var modifiers: Dictionary = system.passive_modifiers(caster, board)
	return float(modifiers.get("damage_vs_restricted", 0.0))


# --- Damage vs a specific enemy element (attacker "element hunter") ----------
#
# The element mirror of the predation bonus above: a PASSIVE AbilityResource on the
# CASTER contributes `rule_modifiers = { "damage_vs_element_nature": 0.5 }` (= +50%
# vs nature-element targets). The key is "damage_vs_element_" + the element name, so
# ONE generic hook serves any element without new plumbing. AbilitySystem sums the
# float exactly like the other numeric modifiers; this reads it and scales the hit.
# Distinct from ElementChart (which keys off the MOVE's element vs the target TYPE) --
# this is keyed off the CASTER's passive vs the target's element, i.e. "I, personally,
# cut grass." Null-safe end to end.


## Multiplier for one hit: 1.0 normally, or 1.0 + the caster's merged
## "damage_vs_element_<target element>" modifier when the target carries that element.
static func _element_bonus_scale(ctx: MoveContext, target) -> float:
	if ctx == null:
		return 1.0
	return element_bonus_scale_for(ctx.caster, target, ctx.board)


## Same element-hunter multiplier, addressed by CASTER/TARGET so the FORECAST
## ([method MoveExecutor.preview_vs]) reads the identical value. Deterministic (it
## depends only on the target's element and the caster's passives), so previewing it
## is honest information.
static func element_bonus_scale_for(caster, target, board = null) -> float:
	if caster == null or target == null:
		return 1.0
	if not target.has_method("get_element"):
		return 1.0
	var elem: String = String(target.get_element())
	if elem == "":
		return 1.0
	var system = null
	if caster.has_method("get_ability_system"):
		system = caster.get_ability_system()
	elif caster.has_method("passive_modifiers"):
		system = caster
	if system == null or not system.has_method("passive_modifiers"):
		return 1.0
	var modifiers: Dictionary = system.passive_modifiers(caster, board)
	var bonus: float = float(modifiers.get("damage_vs_element_" + elem, 0.0))
	if bonus <= 0.0:
		return 1.0
	return 1.0 + bonus


# --- Defender-side damage reduction -----------------------------------------
#
# The mirror image of the predation bonus above. That one reads the ATTACKER's
# passives; nothing let a DEFENDER's passives change what it TAKES, which is what
# "boosted defenses while standing in my grove" needs -- and which a plain defense
# stat modifier cannot express, because defense is subtractive and a fortress boss
# needs the reduction to hold up against big hits too.
#
# Same mechanism, same vocabulary: a PASSIVE AbilityResource on the DEFENDER
# contributes `rule_modifiers = { "damage_taken_scale": 0.75 }` (= takes 25% less)
# and AbilitySystem merges it exactly like every other rule modifier.
#
# MERGING: AbilitySystem._merge_modifiers treats "damage_taken_scale" as a
# STRONGEST-WINS key (it is in STRONGEST_WINS_KEYS), so two passives declaring 0.75
# resolve to 0.75, NOT 1.5 -- reductions refresh to the strongest, they never
# compound. The value is still floored at 0 here so a mis-authored negative can
# never flip damage into healing.


## Multiplier the TARGET's own passives apply to incoming damage: 1.0 normally,
## below 1.0 for a damage reduction, above 1.0 for a vulnerability.
##
## Static and addressed by TARGET/BOARD (not by MoveContext) for exactly the same
## reason as [method restricted_scale_for]: [method MoveExecutor.preview_vs] has no
## context, and the forecast must never disagree with the hit. Deterministic -- it
## depends only on the defender's current state -- so previewing it is honest
## information, not an exploit.
static func damage_taken_scale_for(target, board = null) -> float:
	if target == null:
		return 1.0
	# Two INDEPENDENT sources combine multiplicatively: the defender's PASSIVE ability
	# scale (Eldroot's Grovebound) and its STATUS scale (Braced). One of each -- passive
	# x status -- is not compounding a single source: the status side is itself already
	# reduced to a single "take the strongest" value (see StatusController), and the
	# passive side is a single merged modifier. So a boss standing in its grove that ALSO
	# braces genuinely gets both, while re-bracing can never deepen the status half.
	return _passive_taken_scale(target, board) * _status_taken_scale(target)


## The defender's own PASSIVE "damage_taken_scale" rule modifier (1.0 when it has no
## ability system or no in-force passive declaring one). Floored at 0 so a mis-authored
## negative can never flip damage into healing.
static func _passive_taken_scale(target, board) -> float:
	var system = null
	# A live Unit exposes its component; a test mock may BE the ability system.
	if target.has_method("get_ability_system"):
		system = target.get_ability_system()
	elif target.has_method("passive_modifiers"):
		system = target
	if system == null or not system.has_method("passive_modifiers"):
		return 1.0
	var modifiers: Dictionary = system.passive_modifiers(target, board)
	if not modifiers.has("damage_taken_scale"):
		return 1.0
	return maxf(0.0, float(modifiers["damage_taken_scale"]))


## The single strongest STATUS "damage_taken_scale" on the defender (Braced), 1.0 when
## none. Duck-typed and null-safe: a target with no status controller simply carries no
## status reduction. Reads the "take the strongest" aggregate so two same-kind
## reductions never compound (see StatusController.status_damage_taken_scale).
static func _status_taken_scale(target) -> float:
	if target.has_method("status_damage_taken_scale"):
		return maxf(0.0, float(target.status_damage_taken_scale()))
	if target.has_method("get_status_controller"):
		var controller = target.get_status_controller()
		if controller != null and controller.has_method("status_damage_taken_scale"):
			return maxf(0.0, float(controller.status_damage_taken_scale()))
	return 1.0


## True while [param target] takes NO damage at all.
##
## Sourced from the "invulnerable" RULE FLAG, so it is a timed [StatusCondition]
## (Eldroot's Heartwood Guard grants `guarded`) rather than a stat -- the same
## queried-not-applied mechanism as "immobilized". A PASSIVE ability may also
## declare it as a boolean rule modifier. Duck-typed and independently optional at
## every step, so a mock exposing none of the accessors is simply never invulnerable.
static func is_invulnerable(target) -> bool:
	if target == null:
		return false
	if target.has_method("is_invulnerable") and bool(target.is_invulnerable()):
		return true
	if target.has_method("has_status_rule_flag") and bool(target.has_status_rule_flag(&"invulnerable")):
		return true
	if target.has_method("get_status_controller"):
		var controller = target.get_status_controller()
		if controller != null and controller.has_method("has_rule_flag") \
			and bool(controller.has_rule_flag(&"invulnerable")):
			return true
	if target.has_method("get_ability_system"):
		var system = target.get_ability_system()
		if system != null and system.has_method("passive_modifiers"):
			var modifiers: Dictionary = system.passive_modifiers(target, null)
			if bool(modifiers.get("invulnerable", false)):
				return true
	return false


## Is [param target] movement-restricted right now?
##
## DEFINITION (deliberately narrow, so the bonus is legible to the player):
##   1. an active status sets the "immobilized" rule flag (Ensnared, Ingrained) —
##      the unit cannot move at all; OR
##   2. the unit's CURRENT "movement" stat is below its BASE — i.e. something is
##      actively slowing it (Entangled's negative StatModifierEffect).
##
## A unit that simply has low base movement is NOT restricted — only one that has
## been restricted by something. Both checks are duck-typed and independently
## optional, so a mock exposing neither is never treated as restricted.
static func _is_movement_restricted(target) -> bool:
	if target == null:
		return false
	if target.has_method("is_immobilized") and bool(target.is_immobilized()):
		return true
	if target.has_method("has_status_rule_flag") and bool(target.has_status_rule_flag(&"immobilized")):
		return true
	if target.has_method("get_status_controller"):
		var controller = target.get_status_controller()
		if controller != null and controller.has_method("has_rule_flag") \
			and bool(controller.has_rule_flag(&"immobilized")):
			return true
	if target.has_method("get_stat") and target.has_method("get_base_stat"):
		var base_movement: int = int(target.get_base_stat("movement"))
		# Guard the "no movement stat at all" case: 0 base would make any unit with
		# 0 current movement read as slowed.
		if base_movement > 0 and int(target.get_stat("movement")) < base_movement:
			return true
	return false


func _mitigate(raw: int, target) -> int:
	return _mitigate_for(raw, target, category)


## Category-aware mitigation, addressed by an explicit [param category] rather than
## the effect's own field so it can be reused off-instance (the hazard path below,
## which has no MoveEffect). The instance [method _mitigate] delegates here, so the
## live damage pipeline and the hazard resolve mitigation identically.
static func _mitigate_for(raw: int, target, category_arg) -> int:
	match category_arg:
		CombatTypes.DamageCategory.TRUE:
			return maxi(1, raw)
		CombatTypes.DamageCategory.MAGICAL:
			var res := _stat_or(target, "magic_defense", _stat_or(target, "defense", 0))
			return maxi(1, raw - res)
		_:  # PHYSICAL
			return maxi(1, raw - _stat_or(target, "defense", 0))


## Resolve ONE guaranteed hazard hit against [param target] and return the HP it
## should lose. This is the shared seam a [TravelingHazard] tick calls so that
## environmental lane damage honours the SAME defender-side rules as a normal hit:
##
##   1. "invulnerable" (Heartwood Guard's Guarded) -> a hard 0, short-circuited
##      ahead of everything, exactly as [method apply] does.
##   2. category mitigation (defense / magic_defense; TRUE ignores it).
##   3. the defender's own "damage_taken_scale" passive (Eldroot's Grovebound).
##
## A hazard is environmental, so there is deliberately NO accuracy roll and NO crit
## here -- it always lands and never multiplies. The raw number is snapshotted by
## the caster at CAST time, so a later buff/debuff cannot retune an in-flight vine.
static func resolve_hazard_damage(target, raw: int, category_arg, board) -> int:
	if target == null:
		return 0
	if is_invulnerable(target):
		return 0
	var dealt := _mitigate_for(raw, target, category_arg)
	var taken_scale: float = damage_taken_scale_for(target, board)
	if not is_equal_approx(taken_scale, 1.0):
		dealt = maxi(1, int(round(float(dealt) * taken_scale)))
	return dealt


static func _stat_or(unit, stat_name: String, fallback: int) -> int:
	if unit and unit.has_method("get_stat"):
		var v: int = unit.get_stat(stat_name)
		return v if v > 0 else fallback
	return fallback
