extends Resource
class_name SiegeRuleset

## Data-driven definition of a SIEGE match -- the League-style push mode.
##
## Every number the mode turns on lives here, so retuning Siege is a `.tres` edit rather
## than a code change (the same contract [ArenaRuleset] holds for the Arena). [SiegeController]
## reads exactly these fields; it holds no tuning constants of its own.
##
## DETERMINISM. Nothing here is a probability and nothing here is rolled. Wave cadence, wave
## size, the creep roster and every cap are fixed integers walked in a fixed order, so two
## peers stepping the same command stream spawn the same creeps on the same cells in the same
## sequence. That is what makes the mode lockstep-safe without a seeded RNG (see
## [method SiegeController.wave_creep_id]).

## Human-readable identity, mostly for tooling / a future setup screen.
@export var id: String = "siege_default"
@export var display_name: String = "Siege"
@export_multiline var description: String = ""

# --- Creep waves -------------------------------------------------------------

## A wave is pushed every N full ROUNDS (a round = every side has taken its turn). 3 means
## waves on rounds 3, 6, 9... Values below 1 are clamped to 1 by the controller.
@export var wave_every_rounds: int = 3

## How many creeps each side spawns PER LANE per wave.
@export var creeps_per_lane: int = 2

## Hard cap on how many creeps ONE side may have alive at once. A wave that would exceed it
## is truncated (never skipped wholesale), so a side that is losing its creeps keeps getting
## reinforcements while a side that is snowballing stops flooding the board.
@export var max_live_creeps_per_side: int = 8

## Whether the very first round pushes a wave. Off by default: the opening round is the
## squads' own, and a wave on round 1 lands before either side has moved.
@export var wave_on_first_round: bool = false

## Roster [member CharacterResource.character_id]s a wave is filled from, CYCLED by wave and
## slot index (never rolled). Order is load-bearing: it is the whole spawn sequence.
@export var creep_character_ids: PackedStringArray = PackedStringArray(["tree_grunt"])

# --- March AI ----------------------------------------------------------------

## Manhattan radius within which a marching creep breaks off and fights through the ordinary
## combat AI. Outside it the creep ignores everything and advances along its lane.
@export var creep_aggro_radius: int = 3

# --- Squad respawns ----------------------------------------------------------

## Full ROUNDS a fallen squad unit waits before returning, at the START of a match.
##
## The wait ESCALATES with the round the unit died on (see [method respawn_delay_for_round]):
## an early death costs almost nothing and a late one is a real hole in your line, so the
## opening rounds stay loose and skirmishy while the endgame makes a lost fight matter. Only
## these three knobs shape that curve; the controller holds no numbers of its own.
@export var respawn_base_delay: int = 1

## How many rounds of play buy one extra round of respawn wait.
@export var respawn_rounds_per_step: int = 6

## Ceiling on the wait, however long the match runs. Without it a very long game would put a
## fallen unit out of the match entirely.
@export var respawn_max_delay: int = 3

## Whether squad units respawn at all. Off makes Siege a single-life push.
@export var respawn_enabled: bool = true

## When true a respawned unit comes back with the move cooldowns it died holding; when false
## it returns with a clean moveset. See [SiegeController]'s respawn docs for why "as at death"
## is the shipped default (it is the only choice that needs no clock of its own).
@export var respawn_keeps_cooldowns: bool = true


## [member wave_every_rounds], floored at 1 (a cadence of 0 would spawn every round forever).
func wave_cadence() -> int:
	return maxi(1, wave_every_rounds)


## [member creeps_per_lane], floored at 0.
func wave_size() -> int:
	return maxi(0, creeps_per_lane)


## [member max_live_creeps_per_side]; a negative value means "uncapped".
func creep_cap() -> int:
	return max_live_creeps_per_side


## The wait, in full rounds, for a unit that died on [param round_at_death]:
## [code]clamp(base + floor(round_at_death / rounds_per_step), base, max)[/code].
##
## Pure arithmetic on the DEATH round, which is what makes it lockstep-safe AND fair: the
## number is fixed the instant the unit falls, so a queued respawn's remaining wait can never
## change retroactively because the match ran long. The base is floored at 1 (a delay of 0
## would return a unit on the very round it fell, which reads as the death never happening),
## the step at 1 (a step of 0 is a division by zero), and the ceiling can never sit below the
## base.
##
## With the shipped defaults (base 1, step 6, max 3): a death on round 1-5 waits 1 round,
## round 6-11 waits 2, and round 12 onward waits 3 forever.
func respawn_delay_for_round(round_at_death: int) -> int:
	var base: int = maxi(1, respawn_base_delay)
	var step: int = maxi(1, respawn_rounds_per_step)
	var ceiling: int = maxi(base, respawn_max_delay)
	return clampi(base + (maxi(0, round_at_death) / step), base, ceiling)


## DEPRECATED. The OPENING-round wait, i.e. the shortest this ruleset ever asks for.
##
## The respawn wait stopped being one number when it started escalating, so there is no
## single "the delay" any more. Kept because a caller that just wants to say "respawns take
## about this long" is asking a reasonable question and this is the honest answer to it -- but
## it is NOT what any given unit is actually waiting. For that, read the real computed figure:
## [method SiegeController.respawn_queue] entries carry both the "delay" they were stamped
## with at death and a live "rounds_remaining", and a countdown drawn from those can never
## disagree with when the unit returns.
func respawn_delay() -> int:
	return respawn_delay_for_round(0)
