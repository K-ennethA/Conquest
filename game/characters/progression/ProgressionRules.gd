extends Resource
class_name ProgressionRules

## STORY PROGRESSION's tuning surface (docs/design/PROGRESSION.md; CONQUEST.md rule 11: every number
## is data). Levels, the XP curve, the anti-grind XP formula, stats at level, regional scaling,
## bond and catch rates. The shipped values live in
## res://game/overworld/content/progression_rules.tres; [method current] loads it once.
##
## Levels apply ONLY in story battles: open modes (Skirmish, Versus, Arena, online, replays of
## those) never read this resource.

const RULES_PATH: String = "res://game/overworld/content/progression_rules.tres"

@export_group("Levels")
## The level cap (DECISIONS.md #79). XP past the cap is discarded.
@export_range(1, 200) var max_level: int = 50
## Cumulative XP to REACH level L = round(xp_curve_k * L ^ xp_curve_pow) (level 1 = 0 XP).
@export var xp_curve_k: float = 1.0
@export var xp_curve_pow: float = 3.0
## The level the STARTER joins at (and a [JoinPartyCommand] / starting-party member that names no
## level of its own).
@export_range(1, 200) var starter_level: int = 5
## The level a member of an OLDER save (written before levels existed) loads at.
@export_range(1, 200) var legacy_level: int = 5

@export_group("XP for a defeated foe")
## xp = base_yield * foe_level / xp_level_divisor * level_factor * battle_mult * share
@export var xp_level_divisor: float = 7.0
## level_factor = ((2*Lf + 10) / (Lf + Lm + 10)) ^ xp_level_exp: a stronger foe gives MORE, an
## equal one the baseline, a weaker one LESS (DECISIONS.md #79: anti-grind).
@export var xp_level_exp: float = 2.5
## A foe this many levels (or more) BELOW the member is "grey": its XP is multiplied by
## [member xp_grey_mult] on top of the level factor.
@export_range(0, 100) var xp_grey_gap: int = 5
@export_range(0.0, 1.0, 0.01) var xp_grey_mult: float = 0.1
## A defeated foe that gives anything at all gives at least this much.
@export_range(0, 1000) var xp_min: int = 1
## A species' base XP yield when its [member CharacterResource.xp_yield] is 0 (unset):
## round(power_budget * xp_yield_per_budget), at least [member xp_yield_min] -- stronger species
## give more.
@export var xp_yield_per_budget: float = 0.5
@export_range(1, 10000) var xp_yield_min: int = 10

@export_group("XP battle multipliers")
## battle_mult by battle source: a wild encounter...
@export var battle_mult_wild: float = 1.0
## ...a trainer or scripted battle...
@export var battle_mult_trainer: float = 1.5
## ...a chief or legend battle ([member BattleSpec.boss_battle]).
@export var battle_mult_boss: float = 2.0

@export_group("XP shares")
## share: a member that fought and survived...
@export_range(0.0, 2.0, 0.01) var xp_share_fought: float = 1.0
## ...fought and fell...
@export_range(0.0, 2.0, 0.01) var xp_share_fallen: float = 0.5
## ...sat on the bench (an Exp-Share style setting; 0 = the bench earns nothing).
@export_range(0.0, 2.0, 0.01) var xp_share_bench: float = 0.0
## Multiplier on a LOST battle's XP (0 = a loss earns nothing). A flee / abort never earns XP.
@export_range(0.0, 2.0, 0.01) var xp_on_loss_mult: float = 0.0
## Multiplier on a friendly SPAR's XP (0 = spars earn no XP; they still build bond).
@export_range(0.0, 2.0, 0.01) var xp_spar_mult: float = 0.0

@export_group("Stats at level")
## stat(L) = round(base * (1 + growth * (L - 1))). The growth a stat uses when its species names
## none ([member CharacterResource.health_growth] ... < 0): 0.04 makes level 50 about 3x base.
@export_range(0.0, 1.0, 0.001) var default_growth: float = 0.04
## SPEED scales by this fraction of its growth (speed is identity: turn order should not swing
## wildly with level). MOVEMENT never scales.
@export_range(0.0, 2.0, 0.01) var speed_growth_mult: float = 0.5

@export_group("Regional scaling")
## A LEGEND ([method BattleSpec.make_legend]) is authored at its area band's max + this.
@export_range(0, 50) var legend_over_band: int = 5

@export_group("Bond")
## Bond levels run 0 .. bond_max (DECISIONS.md #68).
@export_range(1, 100) var bond_max: int = 10
## Bond XP per bond level (level n needs n * bond_xp_per_level in total).
@export_range(1, 1000) var bond_xp_per_level: int = 5
## Bond XP for being fielded in a battle (any outcome but a flee / abort)...
@export_range(0, 100) var bond_per_battle: int = 1
## ...or, instead, for being fielded in a WON battle.
@export_range(0, 100) var bond_per_win: int = 2

@export_group("Catch rate")
## A species' catch rate when its [member CharacterResource.catch_rate] is unset (< 0): 1.0 at
## or below [member catch_budget_easy] power budget, [member catch_rate_min] at or above
## [member catch_budget_hard], linear between -- strong species are hard to bond with (#78).
@export var catch_budget_easy: int = 130
@export var catch_budget_hard: int = 240
@export_range(0.0, 1.0, 0.01) var catch_rate_max: float = 1.0
@export_range(0.0, 1.0, 0.01) var catch_rate_min: float = 0.2
## The content validator flags a NON-BOSS story trainer fielding a species below this rate
## ([method Progression.trainer_catch_warnings]).
@export_range(0.0, 1.0, 0.01) var low_catch_rate: float = 0.5

static var _current: ProgressionRules = null


## The shipped rules (cached). Falls back to the script defaults when the .tres is missing.
static func current() -> ProgressionRules:
	if _current == null:
		if ResourceLoader.exists(RULES_PATH):
			_current = load(RULES_PATH) as ProgressionRules
		if _current == null:
			_current = ProgressionRules.new()
	return _current
