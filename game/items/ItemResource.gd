extends Resource
class_name ItemResource

## A PERSISTENT equipment item: a small, permanent buff the player EARNS from play and
## keeps across battles (unlike an [Augment], which lives and dies with one Arena run).
##
## An item is pure data. It carries three independent, composable effect channels, each of
## which [ItemSystem] stamps onto the live [Unit] at battle start:
##
##   1. [member stat_modifiers] -- flat deltas on real engine stats (+5 Max HP, +3 Defense).
##      Author keys with the names [UnitStats] actually knows (see [constant VALID_STATS]);
##      an unknown key is a content bug and is reported by [method validate].
##   2. [member regen_per_turn] -- heal N HP at the start of the unit's turn, held by a
##      battle-long [RegenStatus] on the unit's [StatusController].
##   3. [member damage_reduction_percent] -- a flat "takes N% less damage" band, expressed
##      through the engine's existing [member StatusCondition.damage_taken_scale] channel.
##
## REDUCTIONS REFRESH, THEY NEVER STACK. Two items each granting 10% reduction do NOT make
## 20% (nor 19%): [method StatusController.status_damage_taken_scale] returns the single
## most-protective scale in force, and [ItemSystem] correspondingly applies the STRONGEST
## item reduction rather than a sum or a product. Regen is the one channel that does add
## up across items, because a heal is a resource, not a defensive multiplier -- and it is
## applied as ONE status carrying the summed total, so a re-application still refreshes.
##
## [member scope] decides who an item touches: a UNIT item is equipped to one character and
## buffs only that character's unit; a TEAM item sits in a shared team slot and buffs EVERY
## unit the player fields. Ownership + equipment live in [ItemInventory]; discovery and
## validation live in [ItemLibrary].

## How rare an item is. Drives both the post-battle drop odds ([ItemSystem]) and the
## rarity tint the UI paints it with. Ordered weakest -> strongest.
enum Rarity {
	COMMON,  ## small single-stat boosts; the bread and butter of a collection
	RARE,    ## a movement point, a regen tick, a damage band
	EPIC,    ## team-wide effects and the big numbers
}

## Who the item buffs.
enum Scope {
	UNIT,  ## equipped to ONE character; buffs only that character's unit
	TEAM,  ## sits in a shared team slot; buffs EVERY unit the player fields
}

## Stat keys [UnitStats] can actually carry. Anything outside this set silently does
## nothing at runtime, so [method ItemLibrary.validate] treats it as a content error rather
## than letting a typo ship as a dead item. Mirrors the canonical keys
## [ArenaAugmentApplier] normalizes to -- the same engine path items apply through.
const VALID_STATS: Array[String] = [
	"health",
	"attack",
	"defense",
	"speed",
	"movement",
	"actions",
	"range",
	"range_bonus",
	"magic",
	"magic_defense",
	"evasion",
	"crit",
]

## Stable, UNIQUE key. This is what [ItemInventory] persists and what every save file
## references, so it must never change once an item has shipped (rename the file freely --
## nothing addresses items by path).
@export var id: StringName = &""
@export var display_name: String = "New Item"
@export_multiline var description: String = ""

@export var rarity: Rarity = Rarity.COMMON
@export var scope: Scope = Scope.UNIT

## stat key -> flat delta, e.g. [code]{ "health": 5 }[/code] for +5 Max HP. Keys must be in
## [constant VALID_STATS]. Applied PERMANENTLY for the battle (base + current move together)
## so "+5 max health" really raises the ceiling instead of overfilling the bar.
@export var stat_modifiers: Dictionary = {}

## HP restored to the wearer at the start of each of its turns. 0 = none. Summed across
## every item on the unit and held by a single battle-long [RegenStatus].
@export var regen_per_turn: int = 0

## Percent of incoming damage this item shaves off (0 = none, 25 = takes 25% less). Only the
## STRONGEST such item applies -- see the class docs; reductions refresh, never compound.
@export var damage_reduction_percent: int = 0

## A short glyph/emoji shown beside the name in list UIs. Deliberately a plain String
## rather than a Texture2D so items need no art pipeline to be playable, and so a headless
## test can assert on it.
@export var icon_hint: String = "*"


## Human-readable rarity ("Common" / "Rare" / "Epic").
func rarity_name() -> String:
	return rarity_to_name(rarity)


## Human-readable scope ("Unit" / "Team").
func scope_name() -> String:
	return "Team" if scope == Scope.TEAM else "Unit"


## True when this item buffs the whole squad rather than one character.
func is_team_item() -> bool:
	return scope == Scope.TEAM


## The item's effect as one compact line, e.g. "+5 Max HP" or "Heal 5 / turn". Built from
## the data alone so list UIs never need to duplicate the formatting rules.
func effect_summary() -> String:
	var parts: Array[String] = []
	for raw_key in stat_modifiers.keys():
		var amount: int = int(stat_modifiers[raw_key])
		if amount == 0:
			continue
		var sign_str: String = "+" if amount > 0 else ""
		parts.append("%s%d %s" % [sign_str, amount, pretty_stat(String(raw_key))])
	if regen_per_turn > 0:
		parts.append("Heal %d / turn" % regen_per_turn)
	if damage_reduction_percent > 0:
		parts.append("-%d%% damage taken" % damage_reduction_percent)
	if parts.is_empty():
		return "No effect"
	return ", ".join(parts)


## Rarity enum -> display name. Static so UI can label a rarity without an item in hand.
static func rarity_to_name(value: int) -> String:
	match value:
		Rarity.RARE:
			return "Rare"
		Rarity.EPIC:
			return "Epic"
		_:
			return "Common"


## Display label for a stat key ("health" -> "Max HP"). Kept beside the data it describes so
## every surface that lists an item reads identically.
static func pretty_stat(key: String) -> String:
	match key.strip_edges().to_lower():
		"health":
			return "Max HP"
		"attack":
			return "Attack"
		"defense":
			return "Defense"
		"speed":
			return "Speed"
		"movement":
			return "Move"
		"actions":
			return "Actions"
		"range":
			return "Range"
		"range_bonus":
			return "Reach"
		"magic":
			return "Magic"
		"magic_defense":
			return "Resistance"
		"evasion":
			return "Evasion"
		"crit":
			return "Crit"
	return key.capitalize()
