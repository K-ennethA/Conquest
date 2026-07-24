extends MoveEffect
class_name HealEffect

## Restores health to valid targets in the area (typically ALLY or SELF moves).

@export var amount: int = 20
## Optional caster stat that adds to the heal (e.g. "magic").
@export var scaling_stat: String = ""
@export var scale: float = 1.0
## Fraction of the TARGET's own max health added to the heal (0.10 = 10%).
## Resolved per target, so one cast restores each target its own share.
## 0.0 (the default) leaves the flat heal untouched.
@export var percent_of_max_health: float = 0.0


func apply(ctx: MoveContext) -> void:
	var bonus := 0
	if scaling_stat != "":
		bonus = int(round(ctx.get_caster_stat(scaling_stat) * scale))
	var flat := amount + bonus

	for target in ctx.gather_targets():
		# The percent term reads the TARGET's max health, so it is resolved here
		# rather than once up front.
		var total := flat + _percent_bonus(target)
		# Snapshot HP around the heal so we emit the ACTUAL restored amount (clamped
		# to max by the unit's own heal()), never the raw roll -- a heal into a nearly
		# full unit should announce the sliver it actually recovered, or nothing.
		var before: int = _current_health(target)
		if target.has_method("heal"):
			target.heal(total)
		var healed_amount: int = _current_health(target) - before
		if healed_amount < 0:
			healed_amount = 0
		ctx.log_event({ "effect": "heal", "target": target, "amount": total })
		_announce_heal(target, healed_amount)


## Announce one applied heal on the game-wide bus as
## [code]unit_healed(target, amount)[/code], where amount is the HP ACTUALLY
## restored (clamped to max, >= 0). This is the single emit point for that signal
## -- mirroring how [DamageEffect] is the single emit point for damage_dealt -- and
## it is what lights up the green heal flash in [UnitAnimator] and the heal cue in
## [AudioManager].
##
## Skips a no-op heal (0 restored, e.g. already at full health) and is guarded end
## to end so a headless test with no GameEvents autoload, or a build without the
## signal, simply no-ops.
func _announce_heal(target, healed_amount: int) -> void:
	if target == null or healed_amount <= 0:
		return
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null and GameEvents.has_signal(&"unit_healed"):
		GameEvents.unit_healed.emit(target, healed_amount)


## Read [param target]'s CURRENT health defensively. A live Unit answers through
## [code]get_stat("health")[/code]; test mocks expose a plain [code]hp[/code] or
## [code]current_health[/code]. Returns 0 when none is available, so the heal amount
## simply reads as 0 (and the announce no-ops) rather than erroring.
func _current_health(target) -> int:
	if target == null:
		return 0
	if target.has_method("get_stat"):
		return int(target.get_stat("health"))
	if "current_health" in target:
		return int(target.current_health)
	if "hp" in target:
		return int(target.hp)
	return 0


func describe() -> String:
	if description_override != "":
		return description_override
	if percent_of_max_health <= 0.0:
		return "Restore %d health" % amount
	var pct := roundi(percent_of_max_health * 100.0)
	if amount == 0 and scaling_stat == "":
		return "Restore %d%% of max health" % pct
	return "Restore %d health + %d%% of max health" % [amount, pct]


## [member percent_of_max_health] of [param target]'s max health. Reads the max
## defensively — units expose [code]max_health[/code], some expose
## [code]get_base_stat("health")[/code] — and contributes nothing when the
## percent is off or neither reading is available.
func _percent_bonus(target) -> int:
	if percent_of_max_health <= 0.0 or target == null:
		return 0
	var max_hp := 0
	if "max_health" in target:
		max_hp = int(target.max_health)
	elif target.has_method("get_base_stat"):
		max_hp = int(target.get_base_stat("health"))
	if max_hp <= 0:
		return 0
	return roundi(max_hp * percent_of_max_health)
