extends Resource
class_name MoveResource

## A single move (ability). Standardized as: identity + a [TargetingPattern] +
## an ordered list of [MoveEffect]s. Any combination of effects is legal, so one
## data format expresses everything from a plain melee hit to an area spell that
## damages several enemies, buffs allies, and scorches the terrain at once.
##
## Author these as .tres files (fully inspector-editable) to add content without
## writing code.

@export var move_id: StringName = &""
@export var display_name: String = "New Move"
@export_multiline var description: String = ""
@export var icon: Texture2D

@export var category: CombatTypes.DamageCategory = CombatTypes.DamageCategory.PHYSICAL
## Flavour/type element for UI colour-coding (Pokemon-style): e.g. &"ember",
## &"frost", &"arcane", &"holy", &"nature", &"steel". Empty = neutral (amber).
## See [method ConquestTheme.element_color].
@export var element: StringName = &""
## Resource spent to use the move (energy/mana). 0 = free.
@export var energy_cost: int = 0
## Limited charges per battle. -1 = unlimited.
@export var max_uses: int = -1
## Turns that must pass after use before the move is available again.
## 0 = no cooldown (usable every turn, subject to [member max_uses]).
@export var cooldown: int = 0
## Hit chance 0..1 before the target's evasion is subtracted (resolved by the
## executor / RNG layer). 1.0 = always lands against a 0-evasion target.
@export var accuracy: float = 1.0
## Base critical-hit chance 0..1, added to the caster's "crit" stat. A crit deals
## [constant CombatTypes.CRIT_MULTIPLIER]x damage.
@export var crit_chance: float = 0.0

@export var targeting: TargetingPattern
@export var effects: Array[MoveEffect] = []


func is_valid() -> bool:
	return targeting != null and not effects.is_empty()


## Extra reach [param caster] currently grants to EVERY move it uses, read from
## the unit's [code]"range_bonus"[/code] stat.
##
## Modelled as a stat (rather than, say, a status rule flag) precisely so a plain
## [StatModifierEffect] can grant it with a duration and the existing modifier
## bookkeeping expires it — no new timing code. Null-safe and duck-typed: a null
## caster, or one with no [code]get_stat[/code] (mock boards, legacy units),
## contributes 0.
static func range_bonus_of(caster) -> int:
	if caster == null or not caster.has_method("get_stat"):
		return 0
	return maxi(0, int(caster.get_stat("range_bonus")))


## This move's reach for [param caster] — the authored
## [member TargetingPattern.max_range] plus that caster's range bonus. THE single
## helper every range question resolves through (validation in [MoveExecutor],
## the player's targetable-cell highlight in [UnitActionsPanel], and the AI's
## reachability tests in [BotController]) so they cannot drift apart.
func effective_max_range(caster = null) -> int:
	if targeting == null:
		return 0
	return targeting.effective_max_range(range_bonus_of(caster))


## True if a caster on [param origin] may legally aim this move at [param aim].
##
## [param caster] is optional and trailing: omitted, this resolves exactly as it
## always has (no bonus). Pass the acting unit to honour its range bonus.
func can_aim_at(origin: Vector2i, aim: Vector2i, caster = null) -> bool:
	return targeting != null and targeting.in_range(origin, aim, range_bonus_of(caster))


## The FULL legality test: [method can_aim_at]'s range answer PLUS the pattern's
## board-aware constraints (an empty landing cell, adjacency to an enemy — see
## [method TargetingPattern.is_aim_allowed]).
##
## Split from [method can_aim_at] rather than folded into it because the two
## answer different questions and not every caller has a board: "is this within
## reach?" is pure geometry and drives range previews, while THIS is "may the move
## actually be used here?" and is what [MoveExecutor] validates with. A null board,
## or a pattern declaring no board constraints, makes the two identical.
func can_target(origin: Vector2i, aim: Vector2i, caster = null, board = null) -> bool:
	if targeting == null:
		return false
	return targeting.is_aim_allowed(origin, aim, caster, board, range_bonus_of(caster))


## Build a full description for tooltips: the authored flavor text FOLLOWED BY a
## one-line mechanical summary of every effect. The summary is what surfaces a
## status/knockback/heal CHANCE (e.g. Blight Burst's "50% chance to inflict
## Poisoned") -- it used to be hidden because a move with flavor text returned early
## and never showed its effects. When no flavor is authored, the mechanics stand in
## for the description, with the range appended.
func full_description() -> String:
	var parts: Array[String] = []
	for e in effects:
		if e:
			var d: String = e.describe()
			if d != "":
				parts.append(d)
	var mechanics: String = " · ".join(parts)
	if description != "":
		if mechanics != "":
			return "%s\n%s" % [description, mechanics]
		return description
	var body := mechanics
	if targeting:
		body += " (%s)" % targeting.describe_range()
	return body
