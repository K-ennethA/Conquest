extends RefCounted
class_name ArenaUnitState

## One member of the run's squad, persisting BETWEEN rounds: which character it is, the
## augments stacked on it over the run, and (only for HealPolicy.CARRY_DAMAGE) its
## carried HP. ArenaController rebuilds a live Unit from this each round and re-applies
## the augments, so the "build" you've drafted travels with you across the whole run.

## carried_hp sentinel: full health / not tracked (the FULL_HEAL and CURRENCY modes).
const HP_FULL: int = -1
## carried_hp sentinel: the unit is dead (permadeath under CARRY_DAMAGE).
const HP_DEAD: int = 0

var character_id: String = ""
var augment_ids: Array[String] = []
var carried_hp: int = HP_FULL


func _init(p_character_id: String = "") -> void:
	character_id = p_character_id


func is_alive() -> bool:
	return carried_hp != HP_DEAD


func add_augment(augment_id: String) -> void:
	if augment_id != "" and augment_id not in augment_ids:
		augment_ids.append(augment_id)
