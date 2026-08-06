extends StatusCondition
class_name DelayedBurstStatus

## THE FUSE on a [DelayedBurstHazard] -- a one-turn marker carried by the CASTER that
## erupts the maw it holds when it expires (Monster's Abyssal Maw).
##
## WHY THE FUSE IS A STATUS ON THE CASTER, and not a tick on [HazardManager]. The maw's
## contract is "erupts at the start of the caster's NEXT turn", and the hazard manager
## cannot express that: it advances every live hazard on the active turn system's every
## `turn_started`, which is ANY side's turn, so a maw ticked there would go off on the
## enemy's turn in Traditional and after one intervening unit in Speed First -- a
## different delay per turn system and per player count.
##
## A one-turn status on the caster IS that moment, in both systems, for free. Both turn
## systems drive [method TurnSystemBase._tick_unit_turn_start] for the unit whose turn is
## opening (Speed First for one unit, Traditional for every unit of the side that just
## became active), and that is where [method StatusController.tick_all] decrements and
## expires. A `duration_turns` of 1 therefore expires on precisely the caster's next turn
## start -- riding the ACTIVE turn system's signal, never PlayerManager's
## (CONQUEST.md rule 2).
##
## DETERMINISTIC AND REPLAY-SAFE end to end: the blast cells and the damage number were
## frozen at cast time on the hazard, the fuse length is authored, the expiry beat is the
## same turn-start tick every peer runs, and [method DelayedBurstHazard.detonate] draws
## nothing from any generator. A replay that reissues the same cast command erupts the
## same cells for the same numbers on the same turn.
##
## ONE FUSE AT A TIME, by the ordinary REFRESH rule (CONQUEST.md rule 6): re-casting onto
## a caster that is already carrying one hands the NEW maw to the one live instance and
## resets its timer, rather than banking two eruptions. The move's 3-turn cooldown means
## this is unreachable in play; it is stated here so the behaviour is authored rather
## than accidental.
##
## THE CASTER DYING DEFUSES IT. Its [StatusController] goes with it, and a maw with no
## fuse never goes off -- which is the honest reading of a horror that dies before its
## trap closes, and it costs no bookkeeping to get.

## The armed maw. Runtime state (never exported), so [method Resource.duplicate] hands a
## fresh copy an EMPTY fuse -- the casting effect assigns the live hazard onto the
## instance the controller actually holds.
var hazard = null


## Hand this live instance the maw it should erupt. Called by [DelayedBurstEffect] on the
## instance [method StatusController.add_status] returns (the existing one on a refresh),
## so a re-cast re-arms the single fuse rather than adding a second.
func arm(p_hazard) -> void:
	hazard = p_hazard


## The caster's next turn has begun: the ground opens. Also fired if the fuse is cleansed
## or the controller is cleared -- an unmarked maw simply goes off early, which is
## strictly better than a hazard that can leak past the end of a battle.
func on_expire(_target, board) -> void:
	if hazard == null:
		return
	var live = hazard
	hazard = null  # cleared FIRST, so nothing this announces can re-enter and double-fire
	if not live.has_method("detonate"):
		return
	var result: Dictionary = live.detonate(board)
	_announce_burst(live, result)


## Tell the presentation layer the maw went off, then that it is gone, on the SAME two
## hazard signals the crawling vine uses -- so the existing hazard overlay renders the
## eruption and clears the telegraph with no new visual code.
##
## Guarded end to end: no bus, no such signal, or no autoload (headless suites) all
## no-op, so a cosmetic announce can never fail a mechanics test.
func _announce_burst(live, result: Dictionary) -> void:
	var bus = live.get("event_bus")
	if bus == null:
		if typeof(GameEvents) != TYPE_OBJECT or GameEvents == null:
			return
		bus = GameEvents
	if bus == null or not is_instance_valid(bus):
		return
	if bus.has_signal(&"hazard_advanced"):
		var total: int = 0
		for d in result.get("damaged", []):
			total += int(d.get("amount", 0))
		bus.emit_signal(&"hazard_advanced", live,
			result.get("cells", []), result.get("next_cells", []), total)
	if bus.has_signal(&"hazard_expired"):
		bus.emit_signal(&"hazard_expired", live)
