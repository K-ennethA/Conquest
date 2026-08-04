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
	# Authored power + stat scaling + caster-state power, through the SAME helper the
	# forecast uses, so the two cannot compute a different starting number.
	var raw := DamageMath.raw_power(self, ctx.caster)

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
		# --- Damage order, after mitigation ---------------------------------
		# THE WHOLE post-mitigation chain -- the attacker's predation bonus, the
		# attacker's element-hunter bonus, the defender's own damage_taken_scale, then
		# the ElementChart matchup -- is DamageMath.apply_scales: the SAME function
		# MoveExecutor.preview_vs runs. It is not a copy of the forecast's arithmetic,
		# it IS that arithmetic, so the number the player was shown and the number the
		# board applies cannot drift apart. A caster with no passives hitting a target
		# with no element gets the mitigated number back untouched.
		#
		# Crit is deliberately NOT in the chain: it is ROLLED, and it stays LAST so it
		# multiplies whatever actually got through -- which is what the forecast's
		# crit_damage column claims it does.
		var dealt: int = int(DamageMath.apply_scales(
			_mitigate(raw, target), ctx.caster, target, ctx.move, ctx.board)["total"])
		var crit: bool = outcome.get("crit", false)
		# The escalating bow overrides the per-target crit with the single group roll:
		# the shot either crits every pierced target or none of them.
		if group_crit_scales:
			crit = group_crit
		if crit:
			dealt = maxi(1, int(round(dealt * CombatTypes.CRIT_MULTIPLIER)))
		# ANNOUNCE BEFORE APPLYING. take_damage() can KILL the target outright, and a death
		# synchronously emits unit_eliminated -> the killer's ON_KILL. AbilitySystem
		# attributes that kill through _last_damaged, which is only recorded when this
		# damage_dealt signal fires -- so announcing afterwards meant the victim died before
		# anyone knew who hit it, and ON_KILL abilities (Mortis's Reanimate) silently never
		# fired. Emitting first makes the attacker known by the time the death resolves.
		var controlled_before: bool = is_mind_controlled(target)
		_announce(ctx, target, dealt)
		# THE BLOW THAT SEIZES A HOST DOES NOT ALSO KILL IT.
		#
		# The announce above is the seam where the attacker's ON_ATTACK abilities run (see
		# the ordering note), and one of them -- Mycothrall's Parasitic Hold -- can HAND THE
		# TARGET OVER mid-blow. A takeover that killed its own host in the same instant would
		# be a takeover of a corpse, so the puppet is raised instead: HP is clamped to leave
		# exactly 1, the host is alive to be puppeted, and no elimination fires. Thematically
		# it keeps the host alive while it is effectively dead.
		#
		# Scoped to the EXACT blow that seized the target (the before/after snapshot of the
		# "controlled" rule flag), so an already-controlled unit is killable by the next hit
		# like anything else. Expressed as a RULE FLAG, not as Mycothrall: any future
		# mind-control status inherits this.
		var applied: int = dealt
		if not controlled_before and is_mind_controlled(target):
			applied = mini(dealt, maxi(0, hp_of(target) - 1))
		if applied > 0 and target.has_method("take_damage"):
			target.take_damage(applied)
		total_dealt += applied
		ctx.log_event({
			"effect": "damage",
			"target": target,
			"amount": applied,
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


## Extra RAW power this effect contributes for [param caster], on top of [member power]
## and the stat scaling. 0 for a plain hit; a subclass overrides it to add caster-state
## damage (StackConsumeDamageEffect turns stored charges into power).
##
## Deliberately keyed on the CASTER rather than a MoveContext so the FORECAST can ask the
## same question ([method MoveExecutor.preview_vs] has no context) -- preview and the
## resolved hit therefore agree, and any AI that reads DamageEffect sees the real number.
func bonus_power_for(_caster) -> int:
	return 0


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
##
## The attacker announced is [method MoveContext.damage_credit], NOT the caster: for a
## direct hit those are the same object, and for INDIRECT damage (a status tick, a
## crawling hazard) the credit is the unit that applied it -- or null for nobody. A
## null attacker is a legal, meaningful announcement ("this HP loss belongs to no
## one"), so only the TARGET has to be a real Unit for the typed autoload signal.
static func _announce(ctx: MoveContext, target, dealt: int) -> void:
	if ctx == null or target == null:
		return
	announce_damage(ctx.event_bus, ctx.damage_credit(), target, dealt)


## Emit one [code]damage_dealt(attacker, defender, damage)[/code] on [param bus], or on
## the [code]GameEvents[/code] autoload when [param bus] is null.
##
## Split out of [method _announce] so a damage source with no [MoveContext] can use the
## SAME single emit point: [TravelingHazard] resolves its band damage off-pipeline, and
## before this it announced nothing at all, so a vine kill credited nobody. [param attacker]
## may be null (credit nobody); [param defender] must be a real [Unit] to reach the typed
## autoload signal, exactly as before.
static func announce_damage(bus, attacker, defender, dealt: int) -> void:
	if defender == null:
		return
	if bus == null:
		if not (defender is Unit):
			return
		if attacker != null and not (attacker is Unit):
			return
		bus = GameEvents
	if bus == null or not bus.has_signal(&"damage_dealt"):
		return
	bus.emit_signal(&"damage_dealt", attacker, defender, dealt)


# --- Indirect-damage attribution ---------------------------------------------
#
# THE RULE, in one place, for every indirect damage source (status ticks, traveling
# hazards) so none of them can drift:
#
#   credit the unit that CAUSED the damage -- the status' applier, the vine's caster --
#   while it is still a live unit standing on the board; otherwise credit NOBODY.
#
# Three deliberate refusals:
#   * a FREED source credits nobody (weak references resolve to null, never a dangling
#     object);
#   * a DEAD or off-board source credits nobody -- you cannot earn a kill after you are
#     gone, so a poison that outlives its applier is unattributed;
#   * SELF-INFLICTED damage credits nobody. A unit must never be handed the credit for
#     its own death, which is exactly the bug this replaced: a tick announced with the
#     victim as its own attacker made the victim's AbilitySystem record itself.


## The unit to credit for indirect damage dealt to [param victim] by [param source],
## or null when nobody may be credited. See the rule above.
static func credited_source(source, victim, board = null):
	if source == null or not is_instance_valid(source):
		return null
	if source == victim:
		return null
	if not _is_live(source):
		return null
	if not _is_on_board(source, board):
		return null
	return source


## Is [param unit] still alive? Duck-typed in the project's usual order: a live [Unit]
## answers is_alive(); a mock that only tracks HP is dead at 0; anything exposing neither
## is taken at face value (it cannot be proven dead).
static func _is_live(unit) -> bool:
	if unit.has_method("is_alive"):
		return bool(unit.is_alive())
	if unit.has_method("get_hp"):
		return int(unit.get_hp()) > 0
	return true


## Is [param unit] still ON the board? [BoardAdapter.all_units] already filters the dead,
## so it is the preferred question; a board that only answers placement queries is asked
## whether the unit is standing where it claims to be. A null / query-less board cannot
## answer, and then liveness is all the evidence there is.
static func _is_on_board(unit, board) -> bool:
	if board == null:
		return true
	if board.has_method("all_units"):
		return unit in board.all_units()
	if board.has_method("cell_of") and board.has_method("units_at"):
		return unit in board.units_at(board.cell_of(unit))
	return true


## True while [param target] is under MIND CONTROL, read from the "controlled" rule flag
## a control status ([code]enthralled[/code]) declares. Duck-typed and independently
## optional at every step, exactly like [method is_invulnerable].
##
## Deliberately NOT [method Unit.is_controlled]: that also reports the turn system's
## per-turn forced-control LATCH, which outlives the status by design. This asks only
## "does a status say this unit is somebody else's right now".
static func is_mind_controlled(target) -> bool:
	if target == null:
		return false
	if target.has_method("has_status_rule_flag"):
		return bool(target.has_status_rule_flag(&"controlled"))
	if target.has_method("get_status_controller"):
		var controller = target.get_status_controller()
		if controller != null and controller.has_method("has_rule_flag"):
			return bool(controller.has_rule_flag(&"controlled"))
	return false


## [param target]'s current HP through whichever accessor it exposes (0 when it has
## none). Used by the takeover clamp in [method apply] to leave exactly 1.
static func hp_of(target) -> int:
	if target == null:
		return 0
	if target.has_method("get_hp"):
		return int(target.get_hp())
	if target.has_method("get_stat"):
		return int(target.get_stat("health"))
	return 0


# --- The damage-scaling rules, now owned by DamageMath -----------------------
#
# Predation ("damage_vs_restricted"), the element hunter ("damage_vs_element_<elem>"),
# the defender's own "damage_taken_scale", invulnerability and category mitigation all
# MOVED to [DamageMath] -- the single place the resolved hit and the combat forecast
# now share. What stays here are thin delegations with unchanged signatures, so every
# existing call site (and every test that pins one of these rules) keeps working while
# there is still exactly ONE implementation of each rule.
#
# The dependency runs one way on purpose -- DamageEffect -> DamageMath. DamageMath
# names nothing in this file (it duck-types damage effects instead), so the two can
# never form a reference cycle.


## Predation multiplier for this hit's context.
static func _restricted_scale(ctx: MoveContext, target) -> float:
	if ctx == null:
		return 1.0
	return DamageMath.restricted_scale_for(ctx.caster, target, ctx.board)


## 1.0, or 1.0 + the caster's merged "damage_vs_restricted" when the TARGET cannot get
## away. See [method DamageMath.restricted_scale_for].
static func restricted_scale_for(caster, target, board = null) -> float:
	return DamageMath.restricted_scale_for(caster, target, board)


## Element-hunter multiplier for this hit's context.
static func _element_bonus_scale(ctx: MoveContext, target) -> float:
	if ctx == null:
		return 1.0
	return DamageMath.element_bonus_scale_for(ctx.caster, target, ctx.board)


## 1.0, or 1.0 + the caster's merged "damage_vs_element_<target element>" when the
## target carries that element (Vineweave's Grass Cutter vs nature).
##
## CONDITIONAL ON THE TARGET, never an aura: the modifier key is built from the element
## of the unit actually being hit. The forecast evaluates this SAME function against the
## SAME target, so what the panel promises and what the blow does cannot differ.
## See [method DamageMath.element_bonus_scale_for].
static func element_bonus_scale_for(caster, target, board = null) -> float:
	return DamageMath.element_bonus_scale_for(caster, target, board)


## What the TARGET's own passives and statuses multiply incoming damage by: 1.0
## normally, below for a reduction, above for a vulnerability.
## See [method DamageMath.damage_taken_scale_for].
static func damage_taken_scale_for(target, board = null) -> float:
	return DamageMath.damage_taken_scale_for(target, board)


## True while [param target] takes NO damage at all.
## See [method DamageMath.is_invulnerable].
static func is_invulnerable(target) -> bool:
	return DamageMath.is_invulnerable(target)


## Is [param target] movement-restricted right now?
## See [method DamageMath.is_movement_restricted].
static func _is_movement_restricted(target) -> bool:
	return DamageMath.is_movement_restricted(target)


func _mitigate(raw: int, target) -> int:
	return _mitigate_for(raw, target, category)


## Category-aware mitigation, addressed by an explicit [param category] rather than the
## effect's own field so it can be reused off-instance (the hazard path below, which has
## no MoveEffect). See [method DamageMath.mitigate].
static func _mitigate_for(raw: int, target, category_arg) -> int:
	return DamageMath.mitigate(raw, target, category_arg)



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

