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

# --- Pacing: mode-granted movement -------------------------------------------
#
# A Siege map is LONG -- lanes run the length of the board and a squad that crosses it at
# skirmish pace spends the opening rounds walking. So the mode GRANTS movement, as data:
# every unit of a side that has a base carries a permanent, refresh-safe "March" status worth
# the numbers below (see [method ModeTuning.grant_move_bonus]). Set either to 0 to turn that
# half off entirely; negative is allowed and means the mode SLOWS that kind, which is the
# whole point of a knob rather than a constant.
#
# Read by the engine through [method ModeTuning.hero_move_bonus] /
# [method ModeTuning.creep_move_bonus], which resolve to 0 with no mode armed -- so a plain
# skirmish is untouched (CONQUEST.md rule 11).

## Extra movement every squad HERO of a side with a base is granted for the whole battle.
@export var hero_move_bonus: int = 2

## Extra movement every mode-spawned CREEP is granted. Lower than the heroes' on purpose: the
## creeps are the tide, the squad is what outpaces it.
@export var creep_move_bonus: int = 1

# --- Placed-trap lifetime -----------------------------------------------------

## Full ROUNDS a RUNTIME-PLACED tile effect (a trap a move planted -- Petalfang's Vine Trap
## and anything else laid through [ApplyTileEffect]) survives before it expires and is swept
## off the board.
##
## 0 means NEVER, which is the neutral answer everywhere no mode declares otherwise, so
## skirmish behaviour is byte-identical to before this knob existed. MAP-AUTHORED terrain is
## never touched by it at any value: lava does not expire.
##
## Siege declares 6 because the mode respawns and re-fights over the same lanes for a long
## time -- a permanent trap field authored over twenty rounds stops being a play and starts
## being terrain. The expiry round is FROZEN onto each placement at cast time, exactly the way
## a respawn's wait is frozen at death ([method respawn_delay_for_round]), so retuning this
## mid-match can never retroactively move a trap that is already down.
@export var trap_expiry_rounds: int = 6

# --- Control points (the midpoints) -------------------------------------------
#
# A Siege map may author CONTROL POINTS ([code]MapResource.control_points[/code]) -- cells
# between the two fortresses that either side can take and hold by the same rule that takes a
# base ([CaptureBase]): end your turn standing on one, still be there at your next turn start,
# and it is yours until the enemy repeats the trick. A point held pays its owner in the two
# currencies the mode already runs on, so neither knob invents a new system:
#
#   * REINFORCEMENTS -- extra creeps in that side's wave, entering AT the point and marching
#     the nearest lane. Still bounded by [member max_live_creeps_per_side], so holding every
#     midpoint on the map raises the RATE at which a side reaches its cap, never the cap.
#   * SUSTAIN -- the owner's units standing ON the point are healed at round start, through
#     the ordinary heal pipeline (so the number floats and every heal rule applies).
#
# Both are read off THIS resource by [SiegeController], the same way the wave cadence is: a map
# that authors no control points simply never reaches either, and a mode that wants midpoints
# declares these two knobs on its own ruleset.

## Extra creeps ONE owned control point adds to its owner's wave, spawned AT the point and
## marching the lane nearest it. 0 turns the reinforcement half off and leaves the heal.
@export var control_point_extra_creeps: int = 1

## Health the owner's units standing ON an owned control point are restored at ROUND START.
## Only the OWNER's units: an enemy squatting on your point takes the cell, not the sustain.
## 0 turns the heal half off and leaves the reinforcements.
@export var control_point_heal: int = 5

# --- Neutral-camp reward -------------------------------------------------------

## Full TURNS the buff a felled neutral camp pays the killer's side lasts in this mode.
##
## The camp bounty ([BaseAssaultRuntime]) is otherwise a PERMANENT attack bump that accrues
## for the rest of the battle, which is the right shape for a base assault -- one push, one
## fight. Siege is not that: it respawns both squads and re-fights the same jungle for twenty
## rounds, so a permanent per-kill bump compounds into a lead nothing can answer. Declaring
## this knob converts the reward in THIS mode to a TIMED buff of exactly this many turns,
## refreshed (never stacked) by a second camp kill.
##
## Read by the engine through [method ModeTuning.camp_buff_turns], whose neutral answer is 0 =
## "no timer", i.e. the permanent bounty exactly as it always was. So base assault and every
## other map are untouched (CONQUEST.md rule 11).
@export var camp_buff_turns: int = 5


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


## The movement grant for one unit: [member creep_move_bonus] for a creep, otherwise
## [member hero_move_bonus]. The one place the two knobs are told apart.
func move_bonus_for(is_creep: bool) -> int:
	return creep_move_bonus if is_creep else hero_move_bonus


## [member trap_expiry_rounds], floored at 0 (a negative lifetime is "never", not "already
## expired").
func trap_lifetime() -> int:
	return maxi(0, trap_expiry_rounds)


## [member control_point_extra_creeps], floored at 0 (a negative reinforcement is "none",
## never a creep taken back off the board).
func control_point_creeps() -> int:
	return maxi(0, control_point_extra_creeps)


## [member control_point_heal], floored at 0 (a control point never damages its owner --
## authoring a negative here is a typo, not a hazard).
func control_point_heal_amount() -> int:
	return maxi(0, control_point_heal)


## [member camp_buff_turns], floored at 0 (0 = no timer, i.e. the permanent bounty).
func camp_buff_duration() -> int:
	return maxi(0, camp_buff_turns)
