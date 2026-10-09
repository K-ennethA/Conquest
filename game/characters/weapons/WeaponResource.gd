extends Resource
class_name WeaponResource

## ONE WEAPON a human wields (Fire Emblem style -- DECISIONS.md #54, #63; docs/design/HUMANS.md).
## A human's core action is the WEAPON ATTACK this resource compiles into ([method attack_move]):
## an ordinary [MoveResource] (single enemy, the weapon's reach, its hit / crit / uses) whose one
## effect is a [WeaponStrikeEffect] (might + the wielder's attack or magic, per the type). So the
## strike runs the WHOLE existing pipeline unchanged -- MoveExecutor, the forecast, the AI, the
## command / replay vocabulary (it is just slot 0), the duel compiler.
##
## Content: game/characters/weapons/library/<weapon_id>.tres, indexed by [WeaponLibrary].
## Every number here is a tuning knob.

@export var weapon_id: StringName = &""
@export var display_name: String = "Weapon"
@export_multiline var description: String = ""
## A [WeaponTypeResource] id from [WeaponRules] (&"sword", &"lance", &"axe", &"bow", &"staff", &"tome").
@export var weapon_type: StringName = &"sword"
## MIGHT: the strike's flat power, before the wielder's stat is added.
@export_range(0, 200) var might: int = 10
## HIT: the strike's accuracy 0..1 (before the target's evasion).
@export_range(0.0, 1.0, 0.01) var hit: float = 0.9
## CRIT: base critical chance 0..1 (the wielder's "crit" stat is added on top).
@export_range(0.0, 1.0, 0.01) var crit: float = 0.0
## REACH. 0 = the type's default ([member WeaponTypeResource.default_min_range] / max).
@export_range(0, 12) var min_range: int = 0
@export_range(0, 12) var max_range: int = 0
## USES per battle (Fire Emblem durability, per battle -- nothing breaks for good). -1 = unlimited
## (the default: durability is OFF until the owner wants it).
@export var uses: int = -1
## Optional element of the strike (same vocabulary as moves / [ElementChart]); "" = neutral.
@export var element: StringName = &""
## The strike's name in menus ("Thrust"); "" = the weapon's own name.
@export var attack_name: String = ""
## Fraction of the wielder's scaling stat added to might (1.0 = the full stat, Fire Emblem's
## Str + Mt).
@export_range(0.0, 2.0, 0.01) var stat_scale: float = 1.0
## Marks a stand-in weapon (no designed weapon yet) -- docs and the content audit list them.
@export var placeholder: bool = false

## The compiled strike (built once per weapon; shared and read-only -- consumers that mutate a
## move duplicate it first, CONQUEST.md rule 7).
var _move_cache: MoveResource = null


## This weapon's WEAPON ATTACK as a move (cached). [param rules] = the weapon rules to read the
## type from (default [method WeaponRules.current]).
func attack_move(rules: WeaponRules = null) -> MoveResource:
	if _move_cache != null and rules == null:
		return _move_cache
	var m := build_attack_move(rules if rules != null else WeaponRules.current())
	if rules == null:
		_move_cache = m
	return m


## Build (uncached) the weapon attack under [param rules].
func build_attack_move(rules: WeaponRules) -> MoveResource:
	var t: WeaponTypeResource = rules.type_of(weapon_type) if rules != null else null
	var category: int = t.category if t != null else CombatTypes.DamageCategory.PHYSICAL
	var stat: String = t.scaling_stat if t != null else "attack"
	var reach: Vector2i = reach_with(t)

	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = reach.x
	pattern.max_range = reach.y
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	pattern.area_size = 0

	var strike := WeaponStrikeEffect.new()
	strike.power = maxi(0, might)
	strike.scaling_stat = stat
	strike.scale = stat_scale
	strike.category = category
	strike.weapon_type = weapon_type
	strike.weapon_id = weapon_id

	var m := MoveResource.new()
	m.move_id = move_id_for(weapon_id)
	m.display_name = attack_label()
	m.description = description if not description.is_empty() else "%s strike with %s." % [
		t.display_name if t != null else String(weapon_type).capitalize(), display_name]
	m.category = category
	m.element = element
	m.accuracy = clampf(hit, 0.0, 1.0)
	m.crit_chance = clampf(crit, 0.0, 1.0)
	m.max_uses = uses if uses > 0 else -1
	m.targeting = pattern
	var effects: Array[MoveEffect] = [strike]
	m.effects = effects
	return m


## The move id of a weapon's strike: "weapon_<weapon_id>".
static func move_id_for(p_weapon_id: StringName) -> StringName:
	return StringName("weapon_%s" % String(p_weapon_id))


## True when [param move] is a weapon attack (its damage is a [WeaponStrikeEffect]).
static func is_weapon_move(move) -> bool:
	if move == null or not ("effects" in move):
		return false
	for e in move.effects:
		if e is WeaponStrikeEffect:
			return true
	return false


## The weapon type a [param move] strikes with ("" when it is not a weapon attack).
static func strike_type_of(move) -> StringName:
	if move == null or not ("effects" in move):
		return &""
	for e in move.effects:
		if e is WeaponStrikeEffect:
			return (e as WeaponStrikeEffect).weapon_type
	return &""


## The strike's menu name.
func attack_label() -> String:
	return attack_name if not attack_name.strip_edges().is_empty() else display_name


## The resolved reach (min, max) for type [param t] (its defaults fill an unauthored 0).
func reach_with(t: WeaponTypeResource = null) -> Vector2i:
	var lo: int = min_range if min_range > 0 else (t.default_min_range if t != null else 1)
	var hi: int = max_range if max_range > 0 else (t.default_max_range if t != null else 1)
	lo = maxi(1, lo)
	return Vector2i(lo, maxi(lo, hi))


## Reach under the current rules.
func reach() -> Vector2i:
	return reach_with(WeaponRules.current().type_of(weapon_type))


## Forget the compiled strike (tests that retune a weapon in place).
func clear_cache() -> void:
	_move_cache = null


func validate(rules: WeaponRules = null) -> Array[String]:
	var r: WeaponRules = rules if rules != null else WeaponRules.current()
	var issues: Array[String] = []
	if String(weapon_id).is_empty():
		issues.append("weapon has no weapon_id")
	# "" = typeless (the unarmed fallback): off the triangle, default reach.
	if weapon_type != &"" and not r.has_type(weapon_type):
		issues.append("weapon '%s' has unknown type '%s'" % [weapon_id, weapon_type])
	if max_range > 0 and min_range > max_range:
		issues.append("weapon '%s' min_range %d > max_range %d" % [weapon_id, min_range, max_range])
	if uses == 0:
		issues.append("weapon '%s' has 0 uses (use -1 for unlimited)" % weapon_id)
	return issues
