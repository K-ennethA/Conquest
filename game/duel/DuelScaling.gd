extends RefCounted
class_name DuelScaling

## THE one place a combatant's opaque [member DuelCombatant.strength] turns into stats
## (docs/design/DUEL_BATTLE.md §8.2). Upstream (OVERWORLD / EVOLUTION) has not fixed what
## strength means yet -- a level or a stat scale -- so the duel reads it only here, and a
## change of meaning is a change to this one function.
##
## Current meaning: a STAT SCALE, 1.0 = roster base. It scales the PRIVATE compiled
## character ([DuelCharacter], rule 7) before its unit is built, so every system reads the
## scaled numbers as the unit's own base stats. Speed and movement are left alone (speed
## decides turn order and should stay the unit's identity).

const SCALED_STATS: Array[String] = [
	"base_health", "base_attack", "base_defense", "base_magic", "base_magic_defense",
]


static func apply(character: CharacterResource, strength: float) -> void:
	if character == null or is_equal_approx(strength, 1.0) or strength <= 0.0:
		return
	for stat in SCALED_STATS:
		var base: int = int(character.get(stat))
		character.set(stat, maxi(1, roundi(float(base) * strength)))
