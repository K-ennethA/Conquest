class_name EncounterRoller
extends RefCounted

## DETERMINISTIC wild-encounter rolls (docs/design/OVERWORLD.md §4.5, DECISIONS.md "RNG"):
## a pure function of (journey seed, area, step counter) over a portable hash -- NEVER randf()
## and never the process RNG -- so it is unit-testable, and reloading a save does not re-roll
## the next step (the seed and the counter are in the save).
##
## The hash is 32-bit FNV-1a over a UTF-8 key string: identical on every platform and build,
## unlike anything seeded from the engine's global generator.

const FNV_OFFSET: int = 0x811C9DC5
const FNV_PRIME: int = 0x01000193
const MASK_32: int = 0xFFFFFFFF


## FNV-1a of [param key] as an unsigned 32-bit int.
static func fnv1a(key: String) -> int:
	var h: int = FNV_OFFSET
	for b in key.to_utf8_buffer():
		h = h ^ int(b)
		h = (h * FNV_PRIME) & MASK_32
	return h


## A uniform float in [0, 1) derived from ([param seed], [param key]).
static func unit_float(seed_value: int, key: String) -> float:
	return float(fnv1a("%d|%s" % [seed_value, key])) / 4294967296.0


## Roll the encounter for step [param step] in [param zone]. Returns
## {hit: bool, entry: EncounterEntry | null, roll: float}. Entries whose condition fails under
## [param state] are not in the table for this roll.
static func roll(seed_value: int, area_id: String, step: int, zone: EncounterZone,
		state: StoryState = null) -> Dictionary:
	var miss: Dictionary = {"hit": false, "entry": null, "roll": 1.0}
	if zone == null:
		return miss
	var r: float = unit_float(seed_value, "%s|%d|hit" % [area_id, step])
	miss["roll"] = r
	if r >= zone.rate:
		return miss
	var pool: Array[EncounterEntry] = []
	var total: float = 0.0
	for e in zone.entries():
		if e.weight <= 0.0:
			continue
		if state != null and not ConditionContext.evaluate(e.condition, state):
			continue
		pool.append(e)
		total += e.weight
	if pool.is_empty() or total <= 0.0:
		return miss
	var pick: float = unit_float(seed_value, "%s|%d|pick" % [area_id, step]) * total
	var acc: float = 0.0
	for e in pool:
		acc += e.weight
		if pick < acc:
			return {"hit": true, "entry": e, "roll": r}
	return {"hit": true, "entry": pool[pool.size() - 1], "roll": r}


## A wild creature's STORY LEVEL inside [param band] (docs/design/PROGRESSION.md §3), hashed from
## ([param seed_value], [param key]) -- deterministic like every other roll here. An unset band = 0
## (no level: roster base stats).
static func roll_level(seed_value: int, key: String, band: Vector2i) -> int:
	return Progression.level_in_band(band, unit_float(seed_value, key + "|level"))


## The befriend-offer roll for a won wild battle: deterministic off the BATTLE's seed (so a
## replay reproduces it), never randf(). True when the unit offers to join.
static func befriend_offered(battle_seed: int, chance: float) -> bool:
	if chance <= 0.0:
		return false
	return unit_float(battle_seed, "befriend") < chance
