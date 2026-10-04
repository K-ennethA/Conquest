extends RefCounted
class_name Progression

## STORY PROGRESSION MATHS (docs/design/PROGRESSION.md) -- pure, static, no nodes, no disk beyond
## [method ProgressionRules.current]. Every number comes from a [ProgressionRules]; pass one to pin
## the maths (tests), or null for the shipped rules.
##
##   * levels and the cumulative XP curve ([method xp_for_level], [method level_for_xp]);
##   * XP for a defeated foe with the ANTI-GRIND level factor and grey-level floor
##     ([method xp_for_foe], DECISIONS.md #79);
##   * STATS AT LEVEL -- the ONE function both battle types use ([method apply_level] on a private
##     copy: the duel's compiled character, the tactical spawn's duplicated resource);
##   * scaled levels ([method scaled_level], #80), legend levels ([method legend_level], #81);
##   * bond levels (#68) and per-species XP yield / catch rate (#78).
##
## A level of 0 means "no level" and reads as level 1 everywhere: level 1 IS the roster's base stat
## block, so an unlevelled unit fights exactly as it always did.

## Stats that scale with level (the CharacterResource field and the growth field it reads).
const SCALED_STATS: Array[Array] = [
	["base_health", "health_growth"],
	["base_attack", "attack_growth"],
	["base_defense", "defense_growth"],
	["base_magic", "magic_growth"],
	["base_magic_defense", "magic_defense_growth"],
	["base_speed", "speed_growth"],
]


static func _r(rules: ProgressionRules) -> ProgressionRules:
	return rules if rules != null else ProgressionRules.current()


## [param level] clamped to 1 .. max_level (0 / negative = 1).
static func clamp_level(level: int, rules: ProgressionRules = null) -> int:
	return clampi(level, 1, maxi(1, _r(rules).max_level))


# --- Levels and XP ---------------------------------------------------------------------

## Cumulative XP needed to REACH [param level] (level 1 = 0).
static func xp_for_level(level: int, rules: ProgressionRules = null) -> int:
	var r := _r(rules)
	var l: int = clamp_level(level, r)
	if l <= 1:
		return 0
	return maxi(0, roundi(r.xp_curve_k * pow(float(l), r.xp_curve_pow)))


## The XP total a member is capped at (reaching [member ProgressionRules.max_level]).
static func max_xp(rules: ProgressionRules = null) -> int:
	var r := _r(rules)
	return xp_for_level(r.max_level, r)


## The level a cumulative [param xp] total reaches (1 .. max_level).
static func level_for_xp(xp: int, rules: ProgressionRules = null) -> int:
	var r := _r(rules)
	var level: int = 1
	while level < r.max_level and xp >= xp_for_level(level + 1, r):
		level += 1
	return level


## XP still needed from [param xp] to the next level (0 at the cap).
static func xp_to_next(xp: int, rules: ProgressionRules = null) -> int:
	var r := _r(rules)
	var level: int = level_for_xp(xp, r)
	if level >= r.max_level:
		return 0
	return maxi(0, xp_for_level(level + 1, r) - xp)


## Progress through the current level, 0..1 (1.0 at the cap) -- the XP bar.
static func level_progress(xp: int, rules: ProgressionRules = null) -> float:
	var r := _r(rules)
	var level: int = level_for_xp(xp, r)
	if level >= r.max_level:
		return 1.0
	var lo: int = xp_for_level(level, r)
	var hi: int = xp_for_level(level + 1, r)
	return clampf(float(xp - lo) / float(maxi(1, hi - lo)), 0.0, 1.0)


## The anti-grind LEVEL FACTOR for a foe at [param foe_level] beaten by a member at
## [param member_level]: ((2*Lf + 10) / (Lf + Lm + 10)) ^ xp_level_exp. 1.0 for an equal foe,
## more for a stronger one, less for a weaker one.
static func level_factor(foe_level: int, member_level: int, rules: ProgressionRules = null) -> float:
	var r := _r(rules)
	var lf: float = float(clamp_level(foe_level, r))
	var lm: float = float(clamp_level(member_level, r))
	return pow((2.0 * lf + 10.0) / (lf + lm + 10.0), r.xp_level_exp)


## Is a foe at [param foe_level] GREY for a member at [param member_level] (xp_grey_gap or more
## levels below it)?
static func is_grey(foe_level: int, member_level: int, rules: ProgressionRules = null) -> bool:
	var r := _r(rules)
	return clamp_level(member_level, r) - clamp_level(foe_level, r) >= maxi(1, r.xp_grey_gap)


## XP ONE member at [param member_level] earns for ONE defeated foe:
## base_yield * foe_level / xp_level_divisor * level_factor * battle_mult * share, times
## xp_grey_mult for a grey foe, and never below xp_min -- unless the share or multiplier is 0
## (a bench member, a loss under the default rules), which earns exactly 0.
static func xp_for_foe(base_yield: int, foe_level: int, member_level: int, battle_mult: float,
		share: float, rules: ProgressionRules = null) -> int:
	var r := _r(rules)
	if share <= 0.0 or battle_mult <= 0.0 or base_yield <= 0:
		return 0
	var lf: int = clamp_level(foe_level, r)
	var xp: float = float(base_yield) * float(lf) / maxf(0.001, r.xp_level_divisor) \
		* level_factor(lf, member_level, r) * battle_mult * share
	if is_grey(lf, member_level, r):
		xp *= r.xp_grey_mult
	return maxi(r.xp_min, roundi(xp))


## A species' base XP yield: its authored [member CharacterResource.xp_yield], else derived from
## its power budget.
static func xp_yield_of(character: CharacterResource, rules: ProgressionRules = null) -> int:
	var r := _r(rules)
	if character == null:
		return r.xp_yield_min
	if character.xp_yield > 0:
		return character.xp_yield
	return maxi(r.xp_yield_min, roundi(float(character.power_budget()) * r.xp_yield_per_budget))


## Add [param gained] XP to a member's [param xp] at the cap's limit. Returns {xp, level_before,
## level_after, gained (what actually landed)}.
static func add_xp(xp: int, gained: int, rules: ProgressionRules = null) -> Dictionary:
	var r := _r(rules)
	var before: int = level_for_xp(xp, r)
	var total: int = mini(maxi(0, xp) + maxi(0, gained), max_xp(r))
	total = maxi(total, maxi(0, xp))
	return {"xp": total, "level_before": before, "level_after": level_for_xp(total, r),
		"gained": total - maxi(0, xp)}


# --- Stats at level ------------------------------------------------------------------

## The per-level growth [param character] has for [param growth_field] (its own when set, else
## the rules' default; speed further scaled by speed_growth_mult).
static func growth_for(character: CharacterResource, growth_field: String, rules: ProgressionRules = null) -> float:
	var r := _r(rules)
	var g: float = -1.0
	if character != null and growth_field in character:
		g = float(character.get(growth_field))
	if g < 0.0:
		g = r.default_growth
	if growth_field == "speed_growth":
		g *= r.speed_growth_mult
	return g


## stat(L) = round(base * (1 + growth * (L - 1))), at least 1 for a positive base. Pure.
static func stat_at_level(base: int, growth: float, level: int, rules: ProgressionRules = null) -> int:
	var l: int = clamp_level(level, rules)
	if base <= 0 or l <= 1:
		return base
	return maxi(1, roundi(float(base) * (1.0 + maxf(0.0, growth) * float(l - 1))))


## [param character]'s [param stat_field] ("base_health", ...) at [param level].
static func character_stat(character: CharacterResource, stat_field: String, level: int,
		rules: ProgressionRules = null) -> int:
	if character == null:
		return 0
	var base: int = int(character.get(stat_field))
	for pair in SCALED_STATS:
		if pair[0] == stat_field:
			return stat_at_level(base, growth_for(character, pair[1], rules), level, rules)
	return base


## Max HP of [param character] at [param level].
static func max_hp_at(character: CharacterResource, level: int, rules: ProgressionRules = null) -> int:
	return character_stat(character, "base_health", level, rules)


## THE ONE STAT-AT-LEVEL FUNCTION both battle types use: rewrite [param character]'s scaled base
## stats IN PLACE for [param level]. Only ever call it on a PRIVATE copy (CONQUEST.md rule 7) --
## the duel's compiled DuelCharacter, or [method leveled_copy]'s duplicate. Level <= 1 is a no-op.
static func apply_level(character: CharacterResource, level: int, rules: ProgressionRules = null) -> void:
	if character == null or clamp_level(level, rules) <= 1:
		return
	var vals: Dictionary = {}
	for pair in SCALED_STATS:
		vals[pair[0]] = character_stat(character, pair[0], level, rules)
	for k in vals.keys():
		character.set(k, vals[k])


## A DUPLICATE of [param character] at [param level] (the roster resource is never touched).
## Level <= 1 returns [param character] itself.
static func leveled_copy(character: CharacterResource, level: int, rules: ProgressionRules = null) -> CharacterResource:
	if character == null or clamp_level(level, rules) <= 1:
		return character
	var copy := character.duplicate(false) as CharacterResource
	apply_level(copy, level, rules)
	return copy


# --- Enemy levels --------------------------------------------------------------------

## A SCALED level (chiefs, DECISIONS.md #80): clamp(party_top + offset, lo, hi), within 1..max.
## [param hi] <= 0 = no upper bound beyond max_level.
static func scaled_level(party_top: int, offset: int, lo: int, hi: int, rules: ProgressionRules = null) -> int:
	var r := _r(rules)
	var top: int = maxi(1, party_top) + offset
	var upper: int = hi if hi > 0 else r.max_level
	return clamp_level(clampi(top, mini(lo, upper), upper), r)


## A LEGEND's level (DECISIONS.md #81): its area band's max + legend_over_band. Never scaled.
static func legend_level(band: Vector2i, rules: ProgressionRules = null) -> int:
	var r := _r(rules)
	return clamp_level(maxi(band.x, band.y) + r.legend_over_band, r)


## A normalised band (x <= y, both >= 1), or Vector2i.ZERO for an unset one.
static func normalize_band(band: Vector2i) -> Vector2i:
	if band.x <= 0 and band.y <= 0:
		return Vector2i.ZERO
	var a: int = band.x if band.x > 0 else band.y
	var b: int = band.y if band.y > 0 else band.x
	return Vector2i(mini(a, b), maxi(a, b))


## A level inside [param band] from a uniform [param u] in [0, 1) -- deterministic (the caller
## hashes [param u] from a seed). An unset band = 0 (no level).
static func level_in_band(band: Vector2i, u: float) -> int:
	var b: Vector2i = normalize_band(band)
	if b == Vector2i.ZERO:
		return 0
	var span: int = b.y - b.x + 1
	return b.x + clampi(int(floor(clampf(u, 0.0, 0.999999) * float(span))), 0, span - 1)


# --- Bond and catch rate -----------------------------------------------------------------

## Bond level (0 .. bond_max) of a member with [param bond_xp].
static func bond_level(bond_xp: int, rules: ProgressionRules = null) -> int:
	var r := _r(rules)
	return clampi(maxi(0, bond_xp) / maxi(1, r.bond_xp_per_level), 0, r.bond_max)


## Bond XP a member fielded in a battle earns: bond_per_win on a win, bond_per_battle on any other
## fought outcome; 0 for a flee / abort ([param outcome] "fled" / "aborted") or a bench seat.
static func bond_for_battle(fought: bool, outcome: String, rules: ProgressionRules = null) -> int:
	var r := _r(rules)
	if not fought or outcome == "fled" or outcome == "aborted":
		return 0
	return r.bond_per_win if outcome == "victory" else r.bond_per_battle


## A species' catch / bond rate (0..1): its authored [member CharacterResource.catch_rate], else
## derived from its power budget (linear from catch_rate_max at catch_budget_easy to
## catch_rate_min at catch_budget_hard).
static func catch_rate_of(character: CharacterResource, rules: ProgressionRules = null) -> float:
	var r := _r(rules)
	if character == null:
		return r.catch_rate_max
	if character.catch_rate >= 0.0:
		return clampf(character.catch_rate, 0.0, 1.0)
	var budget: int = character.power_budget()
	var lo: int = r.catch_budget_easy
	var hi: int = maxi(lo + 1, r.catch_budget_hard)
	var t: float = clampf(float(budget - lo) / float(hi - lo), 0.0, 1.0)
	return clampf(lerpf(r.catch_rate_max, r.catch_rate_min, t), 0.0, 1.0)
