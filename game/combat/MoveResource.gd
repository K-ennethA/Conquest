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
## Marks this move as an ULTIMATE -- the big, signature ability that gets the
## full-screen cut-in flash before it resolves (see [UltimateCutIn]). Optional and
## OFF by default: the resolution rule ([method is_ultimate_move]) treats a move as an
## ultimate when this flag is set OR it sits in moveset slot 3 (the 4th move), so every
## existing character's 4th move is an ultimate with zero .tres edits, while a future
## move authored for an EARLIER slot can still opt in by setting this true. Purely
## presentational -- it changes no combat math.
@export var is_ultimate: bool = false
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

@export_group("Alternate mode")
## OPTIONAL SECOND MODE. While the caster holds [member alt_requires_status] -- and does
## NOT hold [member alt_blocked_by_status] -- this move swaps to [member alt_targeting] +
## [member alt_effects]. One move that changes WHAT IT TARGETS and WHAT IT DOES based on
## the caster's own state, instead of two moves eating two slots.
##
## Geode's Prism Bulwark is the case this exists for: normally a SELF-cast guard, but once
## it has absorbed hits and the guard has dropped it becomes an ENEMY-targeted release of
## the stored retaliation -- and reverts to the guard on its own when the charges expire.
##
## Leave [member alt_requires_status] empty (the default) and a move has exactly ONE mode,
## so every move authored before this resolves exactly as it always did.
@export var alt_requires_status: StringName = &""
@export var alt_blocked_by_status: StringName = &""
## Name shown while in alt mode (empty = keep [member display_name]).
@export var alt_display_name: String = ""
@export var alt_targeting: TargetingPattern
@export var alt_effects: Array[MoveEffect] = []

@export_group("Presentation")
## OPTIONAL per-move FX override -- a [MoveFXResource] that retints, resizes or re-sounds
## what [MoveFXDispatcher] draws when this move resolves. Purely cosmetic: nothing in the
## combat layer, the AI, the command vocabulary or a replay reads it, so two peers with
## different FX resolve identical damage.
##
## LEFT NULL (the default, and every move authored before this field existed) the dispatcher
## renders its DERIVED defaults -- the move's element tint, a burst and ground ring on every
## cell its own [TargetingPattern] covers, and a default cue. Authoring is therefore purely
## opt-in polish, never a prerequisite for a move reading on screen.
##
## Typed as plain [Resource] rather than [MoveFXResource] on purpose: a `.tres` referencing
## a brand-new global class only resolves once the engine has rescanned, and a loosely-typed
## field never has that problem. The dispatcher reads it duck-typed for the same reason.
@export var fx: Resource = null


func is_valid() -> bool:
	return targeting != null and not effects.is_empty()


## THE single authority for "does this cast get the ultimate cut-in?". A move is an
## ultimate when its [member is_ultimate] flag is set OR it occupies moveset slot 3 (the
## 4th move) -- so all existing content lights up with zero .tres edits, and a move can
## opt in explicitly from an earlier slot. Null-safe (a null move is never an ultimate);
## [param slot] < 0 (unknown slot) falls back to the flag alone. Static + side-effect free
## so every cast site (human, AI, tests) resolves it identically.
static func is_ultimate_move(move, slot: int = -1) -> bool:
	if move == null:
		return false
	var flagged: bool = ("is_ultimate" in move) and bool(move.is_ultimate)
	return flagged or slot == 3


## True while [param caster]'s current state puts this move in its ALTERNATE mode.
## Always false for a single-mode move, a null caster, or an unauthored alt pattern.
func is_alt_mode(caster = null) -> bool:
	if alt_requires_status == &"" or alt_targeting == null:
		return false
	if not _caster_has_status(caster, alt_requires_status):
		return false
	if alt_blocked_by_status != &"" and _caster_has_status(caster, alt_blocked_by_status):
		return false
	return true


## The pattern this move targets with FOR [param caster]. Every range / legality / preview
## question routes through here, so the UI, the AI and the executor all agree on the mode.
func targeting_for(caster = null) -> TargetingPattern:
	if is_alt_mode(caster):
		return alt_targeting
	return targeting


## The effects this move resolves FOR [param caster].
func effects_for(caster = null) -> Array:
	if is_alt_mode(caster):
		return alt_effects
	return effects


## Display name for [param caster], so the HUD can name the armed mode differently.
func display_name_for(caster = null) -> String:
	if is_alt_mode(caster) and alt_display_name != "":
		return alt_display_name
	return display_name


## Duck-typed, null-safe status probe (mocks / legacy units simply report false).
static func _caster_has_status(unit, id: StringName) -> bool:
	if unit == null or id == &"":
		return false
	if unit.has_method("has_status"):
		return bool(unit.has_status(id))
	if unit.has_method("get_status_controller"):
		var controller = unit.get_status_controller()
		if controller != null and controller.has_method("has_status"):
			return bool(controller.has_status(id))
	return false


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
	var pattern := targeting_for(caster)
	if pattern == null:
		return 0
	return pattern.effective_max_range(range_bonus_of(caster))


## True if a caster on [param origin] may legally aim this move at [param aim].
##
## [param caster] is optional and trailing: omitted, this resolves exactly as it
## always has (no bonus). Pass the acting unit to honour its range bonus.
func can_aim_at(origin: Vector2i, aim: Vector2i, caster = null) -> bool:
	var pattern := targeting_for(caster)
	return pattern != null and pattern.in_range(origin, aim, range_bonus_of(caster))


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
	var pattern := targeting_for(caster)
	if pattern == null:
		return false
	return pattern.is_aim_allowed(origin, aim, caster, board, range_bonus_of(caster))


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
