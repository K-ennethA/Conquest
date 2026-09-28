extends Resource
class_name ConsumableEffect

## What a CONSUMABLE item does when it is USED (docs/design/DECISIONS.md #28 + its revision):
## a HEAL (flat HP and / or a percent of max HP), a CURE (named statuses, or every affliction),
## a REVIVE (a knocked-out party member back on its feet at a percent of max HP) -- any mix.
## An [ItemResource] whose [member ItemResource.consumable] holds one of these is spent from the
## story bag when used: from Journey -> Bag on a party member ([method StoryState.use_consumable]
## via StoryController.use_item_on_member) and in a duel through the Items action (the recorded
## USE_ITEM command, [method NetGameRules._apply]). Pure data + pure rules: the same checks decide
## the bag's "Use on" buttons, the shop's party preview and the duel's item picker, so no screen
## can offer a use the rules would refuse.
##
## THE RULES (one place, so nothing is ever wasted):
##   * a HEAL never overfills (clamped at max HP) and is REFUSED on a member already at full HP
##     ("full_hp") -- and on a KNOCKED-OUT member ("knocked_out"): a tonic does not raise the
##     fallen; that is what a REVIVE is for.
##   * a REVIVE only works on a knocked-out member ("not_knocked_out" otherwise) and leaves it at
##     [member revive_percent] of max HP (at least 1). It only clears the knocked-out / wounded
##     state -- it is not a Wayshrine: the permadeath tiers (DECISIONS.md #29 refinements) decide
##     separately what a FALLEN unit is, and a revive item never touches that.
##   * a CURE removes the named statuses ([member cure_status_ids]) and, with
##     [member cure_all_afflictions], every AFFLICTION -- a condition forced on the unit by a foe
##     or the environment ([method StatusCondition.resolve_clock], CONQUEST.md rule 6a's one
##     classification). A unit's own buffs and battle-long item effects are never touched.
##     Out of battle nothing is carried between battles (a story member keeps HP, never
##     statuses), so a cure-only item is a BATTLE item: the bag says "nothing to cure".

## Flat HP restored (0 = none).
@export var heal_amount: int = 0
## Percent of the target's max HP restored, added to [member heal_amount] (rounded up).
@export_range(0, 100) var heal_percent: int = 0
## Brings a knocked-out member back (see the class docs). Usable only on a knocked-out member.
@export var revive: bool = false
## HP a revive leaves the member at, as a percent of max HP (at least 1 HP).
@export_range(1, 100) var revive_percent: int = 50
## Status ids this removes (e.g. [code]poisoned[/code]).
@export var cure_status_ids: Array[StringName] = []
## Removes every AFFLICTION (hostile / environmental condition) as well.
@export var cure_all_afflictions: bool = false
## Can be used from the bag outside battle.
@export var usable_in_field: bool = true
## Can be used in a duel through the Items action (costs the turn).
@export var usable_in_battle: bool = true

## StoryPartyMember.HP_FULL (members are duck-typed here -- see [method find_status]).
const HP_FULL: int = -1
const STATUS_CATALOG := "res://game/combat/status/StatusCatalog.gd"


# --- What it does ------------------------------------------------------------------

func heals() -> bool:
	return heal_amount > 0 or heal_percent > 0


func cures() -> bool:
	return cure_all_afflictions or not cure_status_ids.is_empty()


## True when it does anything at all (content validation).
func has_effect() -> bool:
	return heals() or cures() or revive


## HP a heal restores to a target with [param max_hp] (before the max-HP clamp).
func heal_for(max_hp: int) -> int:
	var pct: int = int(ceil(float(maxi(0, max_hp)) * float(heal_percent) / 100.0))
	return maxi(0, heal_amount) + pct


## The HP a revive leaves a target with [param max_hp] at.
func revive_hp(max_hp: int) -> int:
	return clampi(int(ceil(float(maxi(1, max_hp)) * float(revive_percent) / 100.0)), 1, maxi(1, max_hp))


## One line for cards and pickers: "Restores 25 HP", "Cures Poisoned", "Revives at 50% HP".
func summary() -> String:
	var parts: Array[String] = []
	if revive:
		parts.append("Revives a knocked-out ally at %d%% HP" % revive_percent)
	if heals():
		var bits: Array[String] = []
		if heal_amount > 0:
			bits.append("%d HP" % heal_amount)
		if heal_percent > 0:
			bits.append("%d%% of max HP" % heal_percent)
		parts.append("Restores " + " + ".join(bits))
	if cure_all_afflictions:
		parts.append("Cures every ailment")
	elif not cure_status_ids.is_empty():
		var names: Array[String] = []
		for id in cure_status_ids:
			names.append(status_label(id))
		parts.append("Cures " + ", ".join(names))
	if parts.is_empty():
		return "No effect"
	var out: String = ". ".join(parts)
	if not usable_in_field and usable_in_battle:
		out += " (battle only)"
	elif usable_in_field and not usable_in_battle:
		out += " (not in battle)"
	return out


## A status id's player-facing name ("poisoned" -> "Poisoned").
static func status_label(id: StringName) -> String:
	var sc = find_status(id)
	if sc != null and not String(sc.display_name).is_empty():
		return String(sc.display_name)
	return String(id).capitalize()


## The shipped StatusCondition declaring [param id] (null when none), looked up through
## StatusCatalog at RUNTIME: items are plain data that tools (the story content builder, which runs
## without autoloads) load, so this file must not pull the combat layer in at compile time.
static func find_status(id: StringName) -> Resource:
	var catalog: Script = load(STATUS_CATALOG) as Script
	if catalog == null:
		return null
	return catalog.call(&"find_by_id", id) as Resource


# --- Out of battle: a story party member ---------------------------------------------

## Could this be used on [param member] right now, OUT OF BATTLE? {ok, reason}; reasons:
## "not_in_field", "no_member", "not_knocked_out", "knocked_out", "full_hp", "nothing_to_cure".
func check_member(member) -> Dictionary:
	if not usable_in_field:
		return _no("not_in_field")
	if member == null:
		return _no("no_member")
	var down: bool = member_is_down(member)
	if revive:
		return _ok() if down else _no("not_knocked_out")
	if down:
		return _no("knocked_out")
	if heals():
		return _ok() if not member.is_full_hp() else _no("full_hp")
	# A cure alone: a story member carries no statuses between battles.
	return _no("nothing_to_cure")


## What using it on [param member] WOULD do, changing nothing (the shop's party preview, the bag's
## buttons): {ok, reason, healed, revived, hp_before, hp_after} -- the same numbers
## [method apply_to_member] then writes.
func preview_member(member) -> Dictionary:
	var check: Dictionary = check_member(member)
	var out: Dictionary = {"ok": bool(check["ok"]), "reason": String(check["reason"]), "healed": 0,
		"revived": false, "hp_before": 0, "hp_after": 0}
	if member == null:
		return out
	var max_hp: int = member.max_hp()
	var before: int = 0 if member_is_down(member) else member.hp_value()
	out["hp_before"] = before
	out["hp_after"] = before
	if not out["ok"]:
		return out
	var hp: int = before
	if revive:
		hp = revive_hp(max_hp)
		out["revived"] = true
	if heals():
		hp = mini(max_hp, hp + heal_for(max_hp))
	out["hp_after"] = hp
	out["healed"] = maxi(0, hp - before)
	return out


## Use it on [param member] (the rules of [method check_member]). The item itself is spent by
## the caller ([method StoryState.use_consumable]). {ok, reason, healed, revived, hp_before, hp_after}.
func apply_to_member(member) -> Dictionary:
	var out: Dictionary = preview_member(member)
	if not out["ok"]:
		return out
	if bool(out["revived"]):
		member.wounded = false
	var hp: int = int(out["hp_after"])
	member.current_hp = HP_FULL if hp >= int(member.max_hp()) else hp
	return out


## A member a revive is for: knocked out in a battle (wounded) or at 0 HP.
## ([param member] is a StoryPartyMember, duck-typed.)
static func member_is_down(member) -> bool:
	return member != null and (bool(member.wounded) or (int(member.current_hp) != HP_FULL and int(member.current_hp) <= 0))


# --- In battle: a live Unit (the duel's USE_ITEM command) -----------------------------

## Could this be used on the live [param unit] now? {ok, reason}; reasons: "not_in_battle",
## "no_target", "knocked_out" (a revive cannot raise a unit mid-duel: a KO ends a 1v1),
## "full_hp", "nothing_to_cure". Duck-typed on the Unit API (get_stat / get_base_stat /
## get_status_controller), so headless doubles work.
func check_unit(unit) -> Dictionary:
	if not usable_in_battle:
		return _no("not_in_battle")
	if unit == null or not is_instance_valid(unit):
		return _no("no_target")
	if unit.has_method("is_alive") and not unit.is_alive():
		return _no("knocked_out")
	if revive and not heals() and not cures():
		return _no("not_knocked_out")
	if heals() and _unit_hp(unit) < _unit_max_hp(unit):
		return _ok()
	if cures() and not curable_on(unit).is_empty():
		return _ok()
	if heals():
		return _no("full_hp")
	return _no("nothing_to_cure")


## The ids of the statuses on [param unit] this would remove (sorted, unique).
func curable_on(unit) -> Array[StringName]:
	var out: Array[StringName] = []
	if unit == null or not unit.has_method("get_status_controller"):
		return out
	var sc = unit.get_status_controller()
	if sc == null or not sc.has_method("get_active"):
		return out
	for cond in sc.get_active():
		if cond == null:
			continue
		var hit: bool = cure_status_ids.has(cond.id)
		if not hit and cure_all_afflictions and cond.has_method("resolve_clock"):
			hit = bool(cond.resolve_clock(unit))
		if hit and not out.has(cond.id):
			out.append(cond.id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Use it on the live [param unit]: cure first, then heal (clamped). Deterministic (no RNG).
## {ok, reason, healed, cured: Array[String]}. The caller annotates the heal for the floating
## text and spends the turn.
func apply_to_unit(unit, board = null) -> Dictionary:
	var check: Dictionary = check_unit(unit)
	var out: Dictionary = {"ok": bool(check["ok"]), "reason": String(check["reason"]), "healed": 0, "cured": []}
	if not out["ok"]:
		return out
	var sc = unit.get_status_controller() if unit.has_method("get_status_controller") else null
	for id in curable_on(unit):
		if sc != null and sc.has_method("remove_status"):
			sc.remove_status(id, board)
			(out["cured"] as Array).append(String(id))
	if heals():
		var before: int = _unit_hp(unit)
		var amount: int = mini(heal_for(_unit_max_hp(unit)), maxi(0, _unit_max_hp(unit) - before))
		if amount > 0 and unit.has_method("heal"):
			unit.heal(amount)
		out["healed"] = maxi(0, _unit_hp(unit) - before)
	return out


static func _unit_hp(unit) -> int:
	if unit.has_method("get_stat"):
		return int(unit.get_stat("health"))
	return int(unit.get("current_health")) if "current_health" in unit else 0


static func _unit_max_hp(unit) -> int:
	if unit.has_method("get_base_stat"):
		return int(unit.get_base_stat("health"))
	if "max_health" in unit:
		return int(unit.max_health)
	return _unit_hp(unit)


## Player-facing words for a refusal reason ("Barkling is already at full HP.").
static func reason_text(reason: String, who: String = "") -> String:
	var name: String = who if not who.is_empty() else "It"
	match reason:
		"full_hp":
			return "%s is already at full HP." % name
		"knocked_out":
			return "%s is knocked out -- only a revive will help." % name
		"not_knocked_out":
			return "%s is not knocked out." % name
		"nothing_to_cure":
			return "%s has nothing to cure." % name
		"not_in_field":
			return "That can only be used in battle."
		"not_in_battle":
			return "That cannot be used in battle."
		"no_target", "no_member":
			return "No one to use it on."
	return "It would have no effect."


static func _ok() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
