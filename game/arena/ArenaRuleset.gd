extends Resource
class_name ArenaRuleset

## Data-driven definition of an Arena MODE. The whole point of the Arena is one engine,
## many modes: solo full-heal, a Slay-the-Spire "Challenge" with currency-bought heals,
## a 1v1 duel, a 3-4 player TFT-style lobby -- every one of those is just a different set
## of values in this resource. ArenaController reads it to drive the round -> draft loop,
## so new modes are authored (a .tres), not coded.

enum HealPolicy {
	FULL_HEAL,     ## squad restored to full (and fallen units returned) each round -- snappy, build-focused
	CURRENCY,      ## limited currency: buy heals, or trade a power-up pick for a heal (Slay-the-Spire feel)
	CARRY_DAMAGE,  ## HP and permadeath persist across rounds -- attrition/roster tension
}

# NB: named WinMode, not WinCondition, to avoid colliding with the existing global
# class_name WinCondition (the map victory-objective system).
enum WinMode {
	SURVIVE_ROUNDS,  ## solo: clear every round
	LAST_STANDING,   ## versus: last player with life remaining
	FIRST_TO_WINS,   ## versus: first to N round-wins
}

@export var id: String = "arena_solo"
@export var display_name: String = "Arena"
@export_multiline var description: String = ""

## 1 = solo vs AI (Phase 1). 2 = 1v1. 3-4 = TFT-style lobby (later phase). The round ->
## draft loop is identical for all; only the opponent wiring changes.
@export var player_count: int = 1
@export var heal_policy: HealPolicy = HealPolicy.FULL_HEAL
@export var win_condition: WinMode = WinMode.SURVIVE_ROUNDS

@export var total_rounds: int = 6
@export var squad_size: int = 4
@export var starting_life: int = 1          ## versus life total; solo ignores it

# --- Draft (reward) step ----------------------------------------------------
@export var augments_per_draft: int = 3
@export var reroll_cost: int = 0

# --- Economy (only meaningful under HealPolicy.CURRENCY) --------------------
@export var starting_currency: int = 0
@export var currency_per_round: int = 0
@export var heal_cost: int = 0

# --- Content pools (empty => ArenaController uses sensible defaults) --------
## Compact arena maps rounds are fought on (cycled/escalated by ArenaController).
@export var arena_map_pool: PackedStringArray = PackedStringArray()
## Directory the draftable Augment resources are loaded from.
@export_dir var augment_pool_dir: String = "res://game/arena/augments"


func is_solo() -> bool:
	return player_count <= 1
