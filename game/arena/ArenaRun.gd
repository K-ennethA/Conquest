extends RefCounted
class_name ArenaRun

## All state that survives BETWEEN rounds of one Arena run: the squad (units + the
## augments stacked on them), currency, the current round, the versus life total, and
## the RNG seed (deterministic drafts now, fair PvP later). Owned by ArenaController and
## discarded when the run ends. Deliberately engine-agnostic (pure data) so it can be
## serialized for save/resume or sent over the wire for versus with no changes.

var squad: Array[ArenaUnitState] = []
var round_index: int = 0                  ## 1-based once a round begins; 0 before start
var currency: int = 0
var life: int = 1                          ## versus life total; solo leaves it at 1
var rng_seed: int = 0
## Squad-wide augments (as opposed to per-unit ones on ArenaUnitState.augment_ids).
var run_augment_ids: Array[String] = []


func add_unit(character_id: String) -> ArenaUnitState:
	var st := ArenaUnitState.new(character_id)
	squad.append(st)
	return st


func living_squad() -> Array[ArenaUnitState]:
	var out: Array[ArenaUnitState] = []
	for u in squad:
		if u != null and u.is_alive():
			out.append(u)
	return out


func has_living_units() -> bool:
	for u in squad:
		if u != null and u.is_alive():
			return true
	return false
