extends Resource
class_name DuelRuleset

## Every number the DUEL mode turns on (docs/design/DUEL_BATTLE.md §8.2), as data
## (CONQUEST.md rule 11). A duel's [DuelBattle] registers itself with [ModeTuning] while it
## runs, so the engine can read any knob declared here through the one surface; the duel's
## own code reads the resource it holds. Retuning a duel is a `.tres` edit
## (`game/duel/rulesets/default_duel.tres`).
##
## Befriend (docs/design/DECISIONS.md): after WINNING a wild duel the defeated unit may offer
## to join. [method join_chance] / [method roll_join] are the pure, tested rule; the roll
## draws from the battle's seeded stream, never randf().

## How the two sides take turns. Only SEQUENTIAL (speed order, each side chooses on its own
## turn) exists in M1; SIMULTANEOUS (blind choice + priority) is the M3 option.
enum TurnMode { SEQUENTIAL, SIMULTANEOUS }

## What the [DuelMoveCompiler] does with an effect class (see [member effect_policies]).
const POLICY_KEEP := "keep"                          ## the effect resolves unchanged
const POLICY_DROP := "drop"                          ## the effect is removed; the move stays
const POLICY_EXCLUDE := "exclude"                    ## the whole move leaves the duel moveset
const POLICY_CONVERT_DAMAGE := "convert_damage"      ## becomes a DamageEffect with the same numbers
const POLICY_KEEP_IF_STATIONARY := "keep_if_stationary"  ## tile effects: kept only if they fire for a unit that never moves
const POLICY_DISABLE := "disable"                    ## abilities: removed from the duel copy

@export_group("Format")
@export var turn_mode: TurnMode = TurnMode.SEQUENTIAL
## Combatants a side may bring: the lead plus (party_size - 1) on the bench. M1 duels are
## strict 1v1 (1); DECISIONS.md #3 targets lead + up to 2 bench (3) with switching in M2/M3.
@export_range(1, 6) var party_size: int = 1
## Voluntary switching (costs the turn). Needs party_size > 1.
@export var allow_switch: bool = false
## KO'd lead is replaced from the bench instead of losing the duel. Needs party_size > 1.
@export var ko_replacement: bool = false
@export var allow_flee: bool = false
@export var allow_items: bool = false
## Cells between the two stations. 4 guarantees no authored AoE aimed at the foe (largest:
## SQUARE 2) also covers the caster's own station.
@export_range(2, 12) var station_gap: int = 4
## Per-unit move clock for human turns, seconds (0 = off; only PvP will want it).
@export var turn_timer_seconds: int = 0

@export_group("Flee (M3)")
@export_range(0.0, 1.0, 0.01) var flee_base: float = 0.5
@export_range(0.0, 0.2, 0.005) var flee_per_speed: float = 0.05
@export_range(0.0, 0.5, 0.01) var flee_per_attempt: float = 0.1
@export_range(0.0, 1.0, 0.01) var flee_min: float = 0.1

@export_group("Befriend")
## Base chance a defeated WILD unit offers to join after a victory.
@export_range(0.0, 1.0, 0.01) var befriend_base_chance: float = 0.25
## Added when the wild unit was SUBDUED (a subdue move left it on exactly 1 HP).
@export_range(0.0, 1.0, 0.01) var befriend_subdue_bonus: float = 0.35

@export_group("Moves")
## Offered when no compiled move is ready (or a unit compiled to none).
@export var struggle_move: MoveResource
## Effect class name -> policy (the DUEL_BATTLE.md §3.4 table as data). A class not listed
## falls back through its base classes, then to [member default_effect_policy].
@export var effect_policies: Dictionary = {}
@export var default_effect_policy: String = POLICY_KEEP
## Ability id -> policy (e.g. reanimate = disable: a KO ends the duel).
@export var ability_policies: Dictionary = {}

@export_group("AI")
## BotController.Difficulty vocabulary: 0 EASY, 1 NORMAL, 2 HARD, 3 BRUTAL.
@export_range(0, 3) var ai_difficulty: int = 1
## Score bonus for a forecast KO that lands at least [member ai_lethal_min_hit] percent.
@export var ai_lethal_bonus: float = 60.0
@export var ai_lethal_min_hit: float = 70.0
## Flat value of a status / debuff by rule flag or kind, times hit chance.
@export var ai_status_values: Dictionary = {
	"stunned": 18.0, "controlled": 16.0, "poisoned": 10.0, "debuff": 6.0, "status": 5.0,
}
## A guard / self-buff is valued when the foe's best expected hit is at least this fraction
## of the actor's HP.
@export_range(0.0, 1.0, 0.01) var ai_guard_threshold: float = 0.3
@export var ai_guard_value: float = 14.0
## A heal is worth this much per missing-HP fraction (0 above [member ai_heal_ceiling]).
@export var ai_heal_value: float = 30.0
@export_range(0.0, 1.0, 0.01) var ai_heal_ceiling: float = 0.8
## Penalty per turn of cooldown for spending a long-cooldown move on a low-value turn.
@export var ai_cooldown_penalty: float = 0.5
## EASY softmax temperature (higher = more random).
@export var ai_easy_temperature: float = 6.0


## The chance a defeated wild unit offers to join: the base chance plus the subdue bonus
## when it was [param subdued], clamped to 0..1. Pure.
func join_chance(subdued: bool) -> float:
	var c: float = befriend_base_chance + (befriend_subdue_bonus if subdued else 0.0)
	return clampf(c, 0.0, 1.0)


## Roll the join offer from [param rng] (the battle's seeded stream -- see
## [method DuelBattle.befriend_rng]). Returns { chance, roll, offered, subdued }. A chance of
## 0 never draws, and 1 always offers, so an authored certainty never shifts the stream.
func roll_join(rng: RandomNumberGenerator, subdued: bool) -> Dictionary:
	var chance: float = join_chance(subdued)
	var roll: float = -1.0
	var offered: bool = false
	if chance >= 1.0:
		offered = true
	elif chance > 0.0 and rng != null:
		roll = rng.randf()
		offered = roll < chance
	return {"chance": chance, "roll": roll, "offered": offered, "subdued": subdued}


## Flee chance (M3; wild duels only): base + speed difference + attempts, clamped. Pure.
func flee_chance(my_speed: int, foe_speed: int, attempts: int) -> float:
	var c: float = flee_base + float(my_speed - foe_speed) * flee_per_speed \
		+ float(maxi(0, attempts)) * flee_per_attempt
	return clampf(c, flee_min, 1.0)


## Bench slots per side ((party_size - 1), 0 in a strict 1v1).
func bench_size() -> int:
	return maxi(0, party_size - 1)


## The policy for an effect whose script chain is [param class_names] (most-derived first).
func policy_for_effect_classes(class_names: Array) -> String:
	for n in class_names:
		if effect_policies.has(String(n)):
			return String(effect_policies[String(n)])
	return default_effect_policy


## The policy for an ability id ("" = keep).
func policy_for_ability(ability_id: StringName) -> String:
	return String(ability_policies.get(String(ability_id), POLICY_KEEP))


## The shipped default ruleset (the one `.tres`), or a code-built copy with the same table
## when the resource is unavailable.
static func load_default() -> DuelRuleset:
	const PATH := "res://game/duel/rulesets/default_duel.tres"
	if ResourceLoader.exists(PATH):
		var rs = load(PATH)
		if rs is DuelRuleset:
			return rs
	var fallback := DuelRuleset.new()
	fallback.effect_policies = default_effect_policy_table()
	fallback.ability_policies = {"reanimate": POLICY_DISABLE}
	return fallback


## The §3.4 policy table, as authored in default_duel.tres (kept here for the fallback and
## the tests that pin it).
static func default_effect_policy_table() -> Dictionary:
	return {
		"DamageEffect": POLICY_KEEP,
		"StackConsumeDamageEffect": POLICY_KEEP,
		"HealEffect": POLICY_KEEP,
		"ShieldEffect": POLICY_KEEP,
		"StatModifierEffect": POLICY_KEEP,
		"ApplyStatusEffect": POLICY_KEEP,
		"PercentHealthLossEffect": POLICY_KEEP,
		"DreadBrandEffect": POLICY_KEEP,
		"InfestEffect": POLICY_KEEP,
		"DelayedBurstEffect": POLICY_KEEP,
		"SetWeatherEffect": POLICY_KEEP,
		"EvolveEffect": POLICY_KEEP,
		"KnockbackEffect": POLICY_DROP,
		"LeapEffect": POLICY_DROP,
		"TileTransformEffect": POLICY_DROP,
		"DashThroughEffect": POLICY_CONVERT_DAMAGE,
		"VoidstepEffect": POLICY_EXCLUDE,
		"SpawnHazardEffect": POLICY_EXCLUDE,
		"SummonEffect": POLICY_EXCLUDE,
		"ApplyTileEffect": POLICY_KEEP_IF_STATIONARY,
	}
