extends RefCounted
class_name DamageMath

## THE damage arithmetic, in ONE place, shared by the resolved hit and the forecast.
##
## WHY THIS EXISTS. [DamageEffect.apply] (what really happens) and
## [MoveExecutor.preview_vs] (what the player is shown) used to walk the same four-step
## post-mitigation chain in two separate hand-written copies. They agreed, but only
## because someone kept them agreeing: every new conditional bonus had to be written
## twice, in the same position, with the same rounding, or the forecast started lying.
## Both now call [method apply_scales], so there is exactly one chain and they cannot
## drift. The forecast is not a model of the damage code — it IS the damage code.
##
## THE CHAIN, in order, each step rounding to a whole HP and flooring at 1:
##   1. PREDATION — the attacker's "damage_vs_restricted" passive, when the target
##      cannot get away.
##   2. ELEMENT HUNTER — the attacker's "damage_vs_element_<elem>" passive, when the
##      target carries that element (Vineweave's Grass Cutter vs nature).
##   3. DEFENDER REDUCTION — the target's own "damage_taken_scale" (passive x status).
##   4. ELEMENT MATCHUP — [ElementChart], move element vs target element, folded with
##      the tile amplifier and the target's own-element tile benefit. When the "move" is
##      an ENVIRONMENTAL source (a tile burning its occupant) this step is the matrix
##      alone — see [method ElementChart.damage_scale_for].
##
## Damage that never had a caster or a move at all — a crawling [TravelingHazard] —
## resolves through [method environment_damage], which is the same steps 3 and 4 in the
## same order with the same rounding.
##
## Attacker bonuses come BEFORE the defender's reduction so the two are commutative
## multipliers on the mitigated number and neither silently dominates. Crit is
## deliberately NOT here: it is rolled, and it stays LAST, applied by the caller, so the
## forecast can report it as a PROBABILITY and never fish for a favourable roll.
##
## EVERY STEP IS DETERMINISTIC. Each depends only on the caster's passives and the
## target's current state — never on RNG, time or turn order — which is both why it is
## honest to preview and why lockstep peers and replays resolve identically.
##
## Deliberately does not reference [DamageEffect]: the dependency runs one way,
## DamageEffect -> DamageMath, and effects are recognised by duck-typing instead (see
## [method is_damage_effect]). DamageEffect keeps thin delegating wrappers so every
## existing call site and test still works.

## The identity multiplier — "nothing applies".
const NEUTRAL: float = 1.0


# --- The shared chain --------------------------------------------------------


## Run the whole post-mitigation chain on [param mitigated] and report both the number
## and WHY it is that number.
##
## Returns:
##   total                  -- int, the damage after every scale (before crit)
##   element_mult           -- float, the full [ElementChart] multiplier applied
##   element_label          -- StringName, [constant ElementChart.LABEL_STRONG] /
##                             LABEL_RESISTED / LABEL_NEUTRAL for that multiplier
##   ability_bonus_percent  -- int, the attacker's CONDITIONAL passive bonuses against
##                             THIS target, as a whole percent (+50 for x1.5, 0 for none)
##   ability_notes          -- Array[String], one human-readable line per conditional
##                             bonus that actually applied, named where nameable
##   defender_scale         -- float, the defender's own damage_taken_scale
static func apply_scales(mitigated: int, caster, target, move, board = null) -> Dictionary:
	var dealt: int = mitigated
	var notes: Array[String] = []

	# 1. Predation: harder into a target that cannot get away.
	var restricted: float = restricted_scale_for(caster, target, board)
	if restricted > NEUTRAL:
		dealt = maxi(1, roundi(float(dealt) * restricted))
		notes.append_array(_notes_for(
			caster, board, "damage_vs_restricted", restricted, "vs a restricted target"))

	# 2. Element hunter: harder into a target of a specific element.
	var hunter: float = element_bonus_scale_for(caster, target, board)
	if hunter > NEUTRAL:
		dealt = maxi(1, roundi(float(dealt) * hunter))
		var elem: String = String(ElementChart.element_of(target))
		notes.append_array(_notes_for(
			caster, board, "damage_vs_element_" + elem, hunter, "vs %s" % elem))

	# 3. The defender's own reduction / vulnerability.
	var taken: float = damage_taken_scale_for(target, board)
	if not is_equal_approx(taken, NEUTRAL):
		dealt = maxi(1, roundi(float(dealt) * taken))

	# 4. Element matchup (+ tile amplifier + own-tile benefit).
	var element_mult: float = ElementChart.damage_scale_for(move, target, board)
	if not is_equal_approx(element_mult, NEUTRAL):
		dealt = maxi(1, roundi(float(dealt) * element_mult))

	return {
		"total": dealt,
		"element_mult": element_mult,
		"element_label": ElementChart.label_for(element_mult),
		"ability_bonus_percent": _as_percent(restricted * hunter),
		"ability_notes": notes,
		"defender_scale": taken,
	}


# --- The ENVIRONMENT's own chain ---------------------------------------------
#
# A crawling hazard resolves OFF the move pipeline: no caster stats, no accuracy, no
# crit -- it always lands, for a number snapshotted at cast time. It still owes the
# defender every defender-side rule a normal hit owes, and (since tiles and hazards are
# elemented) the element matchup as well. This is the whole of it, in the SAME order and
# with the SAME rounding as [method apply_scales]:
#
#   0. INVULNERABLE          -> a hard 0, ahead of everything.
#   1. CATEGORY MITIGATION   -> defense / magic_defense; TRUE ignores it.
#   2. DEFENDER REDUCTION    -> the target's own "damage_taken_scale" (= step 3).
#   3. ELEMENT MATCHUP       -> the SOURCE's element vs the target's (= step 4, on the
#                               environment rule: matrix only).
#
# A tile effect's damage does NOT come through here -- it rides the ordinary
# [DamageEffect] pipeline with an environment-marked move, so it lands on step 4 of
# apply_scales instead. Both roads therefore end at the same [ElementChart] call and
# cannot report different numbers.


## Resolve ONE guaranteed environmental hit and return the HP the target should lose.
## [param source_element] is the tile's / hazard's element (&"" = elementless = neutral).
static func environment_damage(target, raw: int, category_arg, source_element = &"", board = null) -> int:
	if target == null:
		return 0
	if is_invulnerable(target):
		return 0
	var dealt: int = mitigate(raw, target, category_arg)
	var taken: float = damage_taken_scale_for(target, board)
	if not is_equal_approx(taken, NEUTRAL):
		dealt = maxi(1, roundi(float(dealt) * taken))
	var element_mult: float = ElementChart.environment_scale_for(source_element, target)
	if not is_equal_approx(element_mult, NEUTRAL):
		dealt = maxi(1, roundi(float(dealt) * element_mult))
	return dealt


# --- THE forecast ------------------------------------------------------------


## Non-mutating forecast of what [param move] from [param caster] would take off
## [param target]. Rolls nothing; touches nothing.
##
## THE ONE FUNCTION the combat forecast and the resolved hit share, so what the panel
## prints and what the board does are the same arithmetic on the same inputs. Sums every
## damage effect on the move, in the mode actually in force for this caster.
##
## Returns the pinned contract:
##   total                  -- int, damage after mitigation and the full chain (no crit)
##   base                   -- int, damage after mitigation only, before the chain
##   element_mult           -- float, the applied [ElementChart] multiplier
##   element_label          -- StringName, strong / resisted / neutral
##   ability_bonus_percent  -- int, the attacker's conditional bonuses vs THIS target
##   ability_notes          -- Array[String], why
##
## [param board] is optional: a passive's condition may need one to answer (Eldroot's
## Grovebound only reduces damage while it stands on forest). Omitted, conditions that
## need a board fail closed, which under-reports — pass the board when you hold one.
static func preview(caster, target, move, board = null) -> Dictionary:
	var no_notes: Array[String] = []
	var out := {
		"total": 0,
		"base": 0,
		"element_mult": NEUTRAL,
		"element_label": ElementChart.LABEL_NEUTRAL,
		"ability_bonus_percent": 0,
		"ability_notes": no_notes,
	}
	if move == null:
		return out
	# An invulnerable defender takes nothing, so the forecast must SAY nothing —
	# short-circuited here exactly as the resolved hit short-circuits, ahead of
	# mitigation and every scaling step. Showing a mitigated number against a target
	# that will take 0 is the forecast telling a straight lie.
	if is_invulnerable(target):
		return out

	for effect in _damage_effects_of(move, caster):
		var mitigated: int = mitigate(raw_power(effect, caster), target, effect.category)
		var scaled: Dictionary = apply_scales(mitigated, caster, target, move, board)
		out["base"] = int(out["base"]) + mitigated
		out["total"] = int(out["total"]) + int(scaled["total"])
		# The element multiplier and the ability bonuses are properties of the
		# CASTER/TARGET pair, not of an individual effect, so every effect on the move
		# reports the same pair — take them once rather than compounding them.
		out["element_mult"] = scaled["element_mult"]
		out["element_label"] = scaled["element_label"]
		out["ability_bonus_percent"] = scaled["ability_bonus_percent"]
		out["ability_notes"] = scaled["ability_notes"]
	return out


## Raw power of one damage effect for [param caster]: authored power, plus the stat
## scaling, plus any caster-state power the effect contributes (Prism Bulwark's stored
## reprisal charges). Read by the forecast AND by the resolved hit.
static func raw_power(effect, caster) -> int:
	if effect == null:
		return 0
	var bonus: int = 0
	var scaling: String = _text(effect.get("scaling_stat"))
	if scaling != "":
		bonus = roundi(float(_stat(caster, scaling)) * _number(effect.get("scale"), 1.0))
	var extra: int = 0
	if effect.has_method("bonus_power_for"):
		extra = int(effect.bonus_power_for(caster))
	return roundi(_number(effect.get("power"), 0.0)) + bonus + extra


## Category-aware mitigation: the defender's matching defense stat subtracted from
## [param raw], floored at 1. TRUE damage ignores defense entirely; MAGICAL uses
## magic_defense (falling back to defense).
static func mitigate(raw: int, target, category_arg) -> int:
	match category_arg:
		CombatTypes.DamageCategory.TRUE:
			return maxi(1, raw)
		CombatTypes.DamageCategory.MAGICAL:
			return maxi(1, raw - _stat_or(target, "magic_defense", _stat_or(target, "defense", 0)))
		_:  # PHYSICAL
			return maxi(1, raw - _stat_or(target, "defense", 0))


## Is [param effect] a damage effect? Duck-typed on [method DamageEffect.bonus_power_for]
## — the method only [DamageEffect] and its subclasses define — so this file never has
## to name DamageEffect and the dependency stays one-way.
static func is_damage_effect(effect) -> bool:
	return effect != null and effect is Object and effect.has_method("bonus_power_for")


## Every damage effect on [param move], in the mode in force for [param caster].
static func _damage_effects_of(move, caster) -> Array:
	var out: Array = []
	if move == null:
		return out
	var list: Array = move.effects_for(caster) if move.has_method("effects_for") else []
	for effect in list:
		if is_damage_effect(effect):
			out.append(effect)
	return out


# --- Damage vs movement-restricted targets -----------------------------------
#
# Routed through the EXISTING passive-modifier mechanism rather than a bespoke path: a
# PASSIVE AbilityResource contributes `rule_modifiers = { "damage_vs_restricted": 0.5 }`
# (= +50%), AbilitySystem merges it exactly like "extra_actions"/"extra_movement", and
# this reads the merged value. Null-safe end to end — no ability system, no statuses, no
# board, or a mock missing any accessor all resolve to plain damage.


## 1.0 normally, or 1.0 + the caster's merged "damage_vs_restricted" modifier when the
## TARGET is movement-restricted.
static func restricted_scale_for(caster, target, board = null) -> float:
	if caster == null or target == null:
		return NEUTRAL
	if not is_movement_restricted(target):
		return NEUTRAL
	var bonus: float = _modifier_of(caster, board, "damage_vs_restricted")
	return NEUTRAL + bonus if bonus > 0.0 else NEUTRAL


## Is [param target] movement-restricted right now?
##
## DEFINITION (deliberately narrow, so the bonus is legible to the player):
##   1. an active status sets the "immobilized" rule flag (Ensnared, Ingrained) — the
##      unit cannot move at all; OR
##   2. the unit's CURRENT "movement" stat is below its BASE — something is actively
##      slowing it (Entangled's negative StatModifierEffect).
##
## A unit that simply has low base movement is NOT restricted — only one that has been
## restricted by something. Both checks are duck-typed and independently optional, so a
## mock exposing neither is never treated as restricted.
static func is_movement_restricted(target) -> bool:
	if target == null:
		return false
	if target.has_method("is_immobilized") and bool(target.is_immobilized()):
		return true
	if _has_rule_flag(target, &"immobilized"):
		return true
	if target.has_method("get_stat") and target.has_method("get_base_stat"):
		var base_movement: int = int(target.get_base_stat("movement"))
		# Guard the "no movement stat at all" case: 0 base would make any unit with 0
		# current movement read as slowed.
		if base_movement > 0 and int(target.get_stat("movement")) < base_movement:
			return true
	return false


# --- Damage vs a specific enemy element (attacker "element hunter") ----------
#
# The element mirror of the predation bonus: a PASSIVE AbilityResource on the CASTER
# contributes `rule_modifiers = { "damage_vs_element_nature": 0.5 }` (= +50% vs
# nature-element targets). The key is "damage_vs_element_" + the element name, so ONE
# generic hook serves any element without new plumbing.
#
# CONDITIONAL ON THE TARGET, not an aura: the key is built from the element of the unit
# actually being hit, so the bonus applies against a matching target and is simply
# absent against any other. The forecast evaluates the identical condition against the
# identical target, through this identical function.
#
# Distinct from the [ElementChart] matrix, which keys off the MOVE's element vs the
# target's — this is the CASTER's passive vs the target's element, i.e. "I, personally,
# cut grass." The two stack multiplicatively and are meant to.


## 1.0 normally, or 1.0 + the caster's merged "damage_vs_element_<target element>"
## modifier when the target carries that element.
static func element_bonus_scale_for(caster, target, board = null) -> float:
	if caster == null or target == null:
		return NEUTRAL
	# get_element() only — a unit's element is an authored identity, and a mock that
	# does not expose one is deliberately never hunted.
	if not target.has_method("get_element"):
		return NEUTRAL
	var elem: String = String(target.get_element())
	if elem == "":
		return NEUTRAL
	var bonus: float = _modifier_of(caster, board, "damage_vs_element_" + elem)
	return NEUTRAL + bonus if bonus > 0.0 else NEUTRAL


# --- Defender-side damage reduction ------------------------------------------
#
# The mirror of the attacker bonuses. A PASSIVE AbilityResource on the DEFENDER
# contributes `rule_modifiers = { "damage_taken_scale": 0.75 }` (= takes 25% less) and
# AbilitySystem merges it like every other rule modifier.
#
# MERGING: AbilitySystem._merge_modifiers treats "damage_taken_scale" as a
# STRONGEST-WINS key, so two passives declaring 0.75 resolve to 0.75, NOT 1.5 —
# reductions REFRESH to the strongest, they never compound. Floored at 0 here so a
# mis-authored negative can never flip damage into healing.


## Multiplier the TARGET's own state applies to incoming damage: 1.0 normally, below 1.0
## for a reduction, above for a vulnerability.
##
## Two INDEPENDENT sources combine multiplicatively: the defender's PASSIVE ability scale
## (Eldroot's Grovebound) and its STATUS scale (Braced). One of each is not compounding a
## single source — the status side is itself already reduced to a single "take the
## strongest" value, and the passive side is a single merged modifier. So a boss standing
## in its grove that ALSO braces genuinely gets both, while re-bracing can never deepen
## the status half.
static func damage_taken_scale_for(target, board = null) -> float:
	if target == null:
		return NEUTRAL
	return _passive_taken_scale(target, board) * _status_taken_scale(target)


static func _passive_taken_scale(target, board) -> float:
	var system = _ability_system_of(target)
	if system == null or not system.has_method("passive_modifiers"):
		return NEUTRAL
	var modifiers: Dictionary = system.passive_modifiers(target, board)
	if not modifiers.has("damage_taken_scale"):
		return NEUTRAL
	return maxf(0.0, float(modifiers["damage_taken_scale"]))


## The single strongest STATUS "damage_taken_scale" on the defender (Braced), 1.0 when
## none. Reads the "take the strongest" aggregate so two same-kind reductions never
## compound (see StatusController.status_damage_taken_scale).
static func _status_taken_scale(target) -> float:
	if target.has_method("status_damage_taken_scale"):
		return maxf(0.0, float(target.status_damage_taken_scale()))
	if target.has_method("get_status_controller"):
		var controller = target.get_status_controller()
		if controller != null and controller.has_method("status_damage_taken_scale"):
			return maxf(0.0, float(controller.status_damage_taken_scale()))
	return NEUTRAL


## True while [param target] takes NO damage at all.
##
## Sourced from the "invulnerable" RULE FLAG, so it is a timed [StatusCondition]
## (Eldroot's Heartwood Guard grants `guarded`) rather than a stat. A PASSIVE ability may
## also declare it as a boolean rule modifier. Duck-typed and independently optional at
## every step, so a mock exposing none of the accessors is simply never invulnerable.
static func is_invulnerable(target) -> bool:
	if target == null:
		return false
	if target.has_method("is_invulnerable") and bool(target.is_invulnerable()):
		return true
	if _has_rule_flag(target, &"invulnerable"):
		return true
	var system = _ability_system_of(target)
	if system != null and system.has_method("passive_modifiers"):
		if bool(system.passive_modifiers(target, null).get("invulnerable", false)):
			return true
	return false


# --- Shared duck-typed plumbing ----------------------------------------------


## Does [param unit] carry status rule flag [param flag]? Checks the unit's own shortcut
## first, then its status controller. Both optional, so a mock with neither is quietly
## false.
static func _has_rule_flag(unit, flag: StringName) -> bool:
	if unit == null:
		return false
	if unit.has_method("has_status_rule_flag") and bool(unit.has_status_rule_flag(flag)):
		return true
	if unit.has_method("get_status_controller"):
		var controller = unit.get_status_controller()
		if controller != null and controller.has_method("has_rule_flag") \
			and bool(controller.has_rule_flag(flag)):
			return true
	return false


## [param unit]'s ability system. A live [Unit] exposes its component; a test mock may
## BE the ability system.
static func _ability_system_of(unit):
	if unit == null:
		return null
	if unit.has_method("get_ability_system"):
		return unit.get_ability_system()
	if unit.has_method("passive_modifiers"):
		return unit
	return null


## [param unit]'s merged numeric rule modifier [param key] (0.0 when it has no ability
## system, or no in-force passive declaring one).
static func _modifier_of(unit, board, key: String) -> float:
	var system = _ability_system_of(unit)
	if system == null or not system.has_method("passive_modifiers"):
		return 0.0
	return float(system.passive_modifiers(unit, board).get(key, 0.0))


## One note per in-force PASSIVE ability on [param caster] that declares [param key],
## named where it can be named. Falls back to a single anonymous line when the caster's
## abilities cannot be enumerated (a bare mock ability system), so the bonus is never
## reported without a reason.
static func _notes_for(caster, board, key: String, scale: float, context: String) -> Array[String]:
	var out: Array[String] = []
	var percent: int = _as_percent(scale)
	if percent == 0:
		return out
	var system = _ability_system_of(caster)
	var abilities: Variant = system.get("abilities") if system != null else null
	if abilities is Array:
		for ability in (abilities as Array):
			if ability == null:
				continue
			var modifiers: Variant = ability.get("rule_modifiers")
			if not (modifiers is Dictionary) or not (modifiers as Dictionary).has(key):
				continue
			if ability.has_method("is_condition_met") and not ability.is_condition_met(caster, board):
				continue
			var authored: int = _as_percent(NEUTRAL + float((modifiers as Dictionary)[key]))
			out.append("%s: +%d%% %s" % [_name_of_ability(ability), authored, context])
	if out.is_empty():
		out.append("+%d%% %s" % [percent, context])
	return out


static func _name_of_ability(ability) -> String:
	var display: Variant = ability.get("display_name")
	if display is String and display != "":
		return display
	var id: Variant = ability.get("id")
	return String(id) if id != null else "Passive"


## A multiplier as a whole-percent BONUS: 1.5 -> 50, 1.0 -> 0, 0.75 -> -25.
static func _as_percent(scale: float) -> int:
	if not is_finite(scale):
		return 0
	return roundi((scale - NEUTRAL) * 100.0)


## A String / StringName property read back as text; anything else (a missing property
## reads back null) as "". Keeps a duck-typed property read from erroring.
static func _text(value) -> String:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value)
	return ""


## A numeric property read back as a float, or [param fallback] when it is missing or
## is not a number.
static func _number(value, fallback: float) -> float:
	if value is float or value is int:
		return float(value)
	return fallback


static func _stat(unit, stat_name: String) -> int:
	if unit != null and unit.has_method("get_stat"):
		return int(unit.get_stat(stat_name))
	return 0


static func _stat_or(unit, stat_name: String, fallback: int) -> int:
	if unit != null and unit.has_method("get_stat"):
		var v: int = int(unit.get_stat(stat_name))
		return v if v > 0 else fallback
	return fallback
