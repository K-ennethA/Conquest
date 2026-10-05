class_name WildSpawner
extends RefCounted

## VISIBLE, GRID-LOCKED WILD CREATURES (docs/STORY_MODE.md "Visible wild creatures"; the
## Let's Go / Mystery Dungeon "symbol encounter" decision). The pure-logic core: no nodes, no
## disk, no randf() -- the [OverworldController] mounts an [OverworldActor] per creature and asks
## this class what moved.
##
## * ROSTER. Each [constant EncounterZone.Mode.VISIBLE] zone holds up to
##   [member EncounterZone.max_active] creatures, one per SLOT. A slot's species and cell are a
##   pure function of (journey seed, area, zone, roster EPOCH, slot) over [EncounterRoller]'s
##   FNV-1a hash; entries whose condition fails are not in the pool.
## * MOVEMENT. One cell per PLAYER STEP ([method tick]), never in real time, in slot order. Every
##   choice is hashed from (seed, area, zone, slot, step counter). Behaviours
##   ([enum EncounterEntry.Behaviour]): wander (leashed to the zone's cells), timid (steps away
##   from the hero within its sense range), aggressive ([TrainerSight] along its facing: "!" and
##   it closes in), sleeping (never moves), patrol (an authored waypoint loop).
## * CONTACT. The hero walking into a creature: [method contact_opening] -- its back / side (or
##   asleep) = [constant BattleRequest.OPENING_AMBUSH], face to face = neutral. A creature walking
##   into the hero = [constant BattleRequest.OPENING_AMBUSHED].
## * PERSISTENCE ([member StoryState.wild], saved as "wild"). Per zone: the epoch, the respawn
##   mark, the visit its cells were laid out in, and the LIVE slots {cid, cell, facing, wp}. A
##   beaten / befriended creature's slot is removed ([method forget]); missing slots are refilled
##   when the zone's [member EncounterZone.respawn] rule fires (a new epoch). Within one visit
##   (a battle round trip, a save + reload) every creature stands exactly where it stood; a new
##   visit lays the survivors out afresh (away from the arrival cell).
##
## Grid: every creature is a BLOCKER on the [OverworldGrid] (id [method blocker_id]), so NPC
## pathing / tap paths go round it (sight is NOT blocked: trainers and aggressive creatures look
## over a creature in the grass); the controller checks
## [method creature_at] BEFORE walkability so walking into one is contact, not a bump.

const BLOCKER_PREFIX := OverworldGrid.WILD_BLOCKER_PREFIX
const DIRS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
## Slots per zone are capped here (the save sanitizer trusts nothing above it).
const MAX_SLOTS: int = 8


## One creature on the map.
class WildCreature:
	extends RefCounted
	## "<zone key>#<slot>" -- unique within the area.
	var key: String = ""
	var zone_key: String = ""
	var zone: EncounterZone = null
	var slot: int = 0
	var entry: EncounterEntry = null
	var cell: Vector3i = Vector3i.ZERO
	var facing: Vector2i = Vector2i(0, 1)
	## PATROL: the index of the waypoint it walks toward.
	var waypoint: int = 0
	## AGGRESSIVE: it has spotted the hero (this tick).
	var alerted: bool = false
	## Its STORY LEVEL (rolled from the zone's band at spawn, saved as "lv"); 0 = no level.
	var level: int = 0

	func character_id() -> String:
		return String(entry.character_id) if entry != null else ""

	func behaviour() -> int:
		return entry.behaviour if entry != null else EncounterEntry.Behaviour.WANDER

	func _to_string() -> String:
		return "Wild(%s %s @%s)" % [key, character_id(), str(cell)]


var area: OverworldAreaResource = null
var grid: OverworldGrid = null
var state: StoryState = null
var area_id: String = ""
## Live creatures, zone order then slot order (the tick order).
var creatures: Array[WildCreature] = []
## zone key -> EncounterZone (visible zones only), in area order.
var _zones: Dictionary = {}
var _zone_order: Array[String] = []
## zone key -> Array[Vector3i]: the zone's cells a creature may stand on (sorted, deterministic).
var _cells: Dictionary = {}
## zone key -> {Vector3i: true} (leash lookups).
var _cell_set: Dictionary = {}


static func create(p_area: OverworldAreaResource, p_grid: OverworldGrid, p_state: StoryState) -> WildSpawner:
	var w := WildSpawner.new()
	w.area = p_area
	w.grid = p_grid
	w.state = p_state
	w.area_id = String(p_area.area_id) if p_area != null else ""
	w._index_zones()
	return w


## The grid blocker id of the creature [param key].
static func blocker_id(key: String) -> String:
	return BLOCKER_PREFIX + key


## The [member StoryState.wild] record key of a zone.
static func record_key(p_area_id: String, zone_key: String) -> String:
	return "%s|%s" % [p_area_id, zone_key]


## True when the area has at least one VISIBLE zone.
func has_zones() -> bool:
	return not _zone_order.is_empty()


func creature_at(cell: Vector3i) -> WildCreature:
	for c in creatures:
		if c.cell == cell:
			return c
	return null


func creature(key: String) -> WildCreature:
	for c in creatures:
		if c.key == key:
			return c
	return null


## The cells creatures of [param zone_key] may stand on (tests / tools).
func zone_cells(zone_key: String) -> Array:
	return _cells.get(zone_key, [])


# =====================================================================================
#  Roster (area load, respawns)
# =====================================================================================

## Lay the roster out for an area load with the hero on [param player_cell]: apply each zone's
## respawn rule, keep / re-place / roll its slots, persist, and register the grid blockers.
func sync(player_cell: Vector3i) -> void:
	creatures.clear()
	if state == null or grid == null:
		return
	for zk in _zone_order:
		var zone: EncounterZone = _zones[zk]
		var rkey: String = record_key(area_id, zk)
		var rec: Dictionary = state.wild.get(rkey, {})
		var fresh: bool = rec.is_empty()
		if fresh or _renew_due(zone, rec):
			rec = {"epoch": 0 if fresh else int(rec.get("epoch", 0)) + 1, "mark": _mark_now(zone),
				"visit": state.visit_serial, "slots": {}}
			state.wild[rkey] = rec
			for slot in range(_slot_count(zone)):
				var c := _roll_slot(zk, zone, int(rec["epoch"]), slot, player_cell)
				if c != null:
					_adopt(c)
		else:
			var new_visit: bool = int(rec.get("visit", -1)) != state.visit_serial
			rec["visit"] = state.visit_serial
			var slots: Dictionary = rec.get("slots", {})
			for sk in _sorted_slot_keys(slots):
				var c := _restore_slot(zk, zone, int(sk), slots[sk])
				if c == null:
					continue
				# A new visit (or a cell the content no longer allows): lay it out afresh, away
				# from where the hero arrives. Same visit (a battle round trip, a reload): stays put.
				if new_visit or not _can_stand(c, c.cell, player_cell, 0):
					var at: Vector3i = _pick_cell(zk, zone, int(rec.get("epoch", 0)), c.slot, player_cell,
						"visit%d" % state.visit_serial, c.entry)
					if at == Cells.INVALID:
						continue
					c.cell = at
				_adopt(c)
			state.wild[rkey] = rec
	_persist_all()


## Refill the empty slots of every zone whose respawn rule fired while the hero is IN the area
## (EVERY_N_STEPS after a step, ON_REST after a Wayshrine rest). Survivors never move. Returns the
## creatures that appeared (the controller mounts them).
func refresh_respawns(player_cell: Vector3i) -> Array[WildCreature]:
	var out: Array[WildCreature] = []
	if state == null:
		return out
	for zk in _zone_order:
		var zone: EncounterZone = _zones[zk]
		var rkey: String = record_key(area_id, zk)
		var rec: Dictionary = state.wild.get(rkey, {})
		if rec.is_empty() or not _renew_due(zone, rec):
			continue
		rec["epoch"] = int(rec.get("epoch", 0)) + 1
		rec["mark"] = _mark_now(zone)
		for slot in range(_slot_count(zone)):
			if creature("%s#%d" % [zk, slot]) != null:
				continue
			var c := _roll_slot(zk, zone, int(rec["epoch"]), slot, player_cell)
			if c != null:
				_adopt(c)
				out.append(c)
		state.wild[rkey] = rec
	if not out.is_empty():
		_sort_creatures()
		_persist_all()
	return out


## The creature [param key] was beaten or befriended: it leaves the map and its slot stays empty
## until the zone respawns.
func remove(key: String) -> void:
	var c := creature(key)
	if c == null:
		return
	creatures.erase(c)
	if grid != null and grid.blocker_at(c.cell) == blocker_id(key):
		grid.clear_blocker(c.cell)
	forget(state, area_id, key)


## Drop creature [param key] of [param p_area_id] from the saved roster (no live spawner needed:
## the post-battle script runs this before the overworld has re-read the state).
static func forget(p_state: StoryState, p_area_id: String, key: String) -> void:
	if p_state == null or key.is_empty():
		return
	var parts: PackedStringArray = key.rsplit("#", true, 1)
	if parts.size() != 2:
		return
	var rkey: String = record_key(p_area_id, parts[0])
	var rec: Dictionary = p_state.wild.get(rkey, {})
	var slots: Dictionary = rec.get("slots", {})
	slots.erase(parts[1])


## (Re-)register every creature's grid blocker (after [method OverworldGrid.rebuild_blockers]).
func register_blockers() -> void:
	if grid == null:
		return
	for c in creatures:
		grid.set_blocker(c.cell, blocker_id(c.key))


# =====================================================================================
#  The step clock
# =====================================================================================

## Every creature takes its step after the hero arrived on [param player_cell] (state.steps is
## already this step's count). With [param allow_contact] false (grace steps, no partner) a
## creature that would walk into the hero stops instead. Returns
## {contact: WildCreature | null, moved: Array[WildCreature], turned: Array[WildCreature],
##  alerted: Array[WildCreature]}. Processing stops at the first contact.
func tick(player_cell: Vector3i, allow_contact: bool = true) -> Dictionary:
	var out: Dictionary = {"contact": null, "moved": [] as Array[WildCreature],
		"turned": [] as Array[WildCreature], "alerted": [] as Array[WildCreature]}
	for c in creatures:
		c.alerted = false
		var r: Dictionary = _step_creature(c, player_cell, allow_contact)
		if bool(r.get("alerted", false)):
			c.alerted = true
			(out["alerted"] as Array).append(c)
		if bool(r.get("moved", false)):
			(out["moved"] as Array).append(c)
		elif bool(r.get("turned", false)):
			(out["turned"] as Array).append(c)
		if bool(r.get("contact", false)):
			out["contact"] = c
			break
	_persist_all()
	return out


## The opening when the HERO walks into [param c] from [param from_cell]: a sleeping creature, or
## one whose back / side is to the hero, is caught unaware ([constant BattleRequest.OPENING_AMBUSH]);
## one looking straight at the hero is a fair start ([constant BattleRequest.OPENING_NEUTRAL]).
static func contact_opening(c: WildCreature, from_cell: Vector3i) -> String:
	if c == null:
		return BattleRequest.OPENING_NEUTRAL
	if c.behaviour() == EncounterEntry.Behaviour.SLEEPING:
		return BattleRequest.OPENING_AMBUSH
	var toward_hero := Vector2i(signi(from_cell.x - c.cell.x), signi(from_cell.y - c.cell.y))
	if c.facing == toward_hero:
		return BattleRequest.OPENING_NEUTRAL
	return BattleRequest.OPENING_AMBUSH


## Turn [param c] to face [param cell] (contact: the creature turns to the hero) and persist it.
func face(c: WildCreature, cell: Vector3i) -> void:
	if c == null:
		return
	var d := Vector2i(cell.x - c.cell.x, cell.y - c.cell.y)
	if d == Vector2i.ZERO:
		return
	c.facing = Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	_persist_all()


func _step_creature(c: WildCreature, player_cell: Vector3i, allow_contact: bool) -> Dictionary:
	var e: EncounterEntry = c.entry
	match c.behaviour():
		EncounterEntry.Behaviour.SLEEPING:
			return {}
		EncounterEntry.Behaviour.PATROL:
			if e.patrols():
				return _step_patrol(c, player_cell, allow_contact)
		EncounterEntry.Behaviour.AGGRESSIVE:
			if TrainerSight.spots(grid, c.cell, c.facing, e.sense_range, player_cell):
				var next := _offset(c.cell, c.facing)
				if next == player_cell:
					return {"alerted": true, "contact": allow_contact}
				if _can_stand(c, next, player_cell, -1):
					_move(c, next)
					return {"alerted": true, "moved": true}
				return {"alerted": true}
		EncounterEntry.Behaviour.TIMID:
			var dist: int = Cells.manhattan_2d(c.cell, player_cell)
			if dist <= e.sense_range:
				return _step_flee(c, player_cell, dist)
	return _step_wander(c, player_cell)


func _step_wander(c: WildCreature, player_cell: Vector3i) -> Dictionary:
	var e: EncounterEntry = c.entry
	if _roll(c, "move") >= e.move_chance:
		# Idle: now and then it looks around (an aggressive one sweeps its sight this way).
		if _roll(c, "look") < 0.35:
			var d: Vector2i = DIRS[int(_roll(c, "lookdir") * 4.0) % 4]
			if d != c.facing:
				c.facing = d
				return {"turned": true}
		return {}
	var start: int = int(_roll(c, "dir") * 4.0) % 4
	for i in range(4):
		var d: Vector2i = DIRS[(start + i) % 4]
		var to := _offset(c.cell, d)
		if _can_stand(c, to, player_cell, -1):
			_move(c, to)
			return {"moved": true}
	return {}


func _step_flee(c: WildCreature, player_cell: Vector3i, dist: int) -> Dictionary:
	var best: Array[Vector3i] = []
	var best_d: int = dist
	for d in DIRS:
		var to := _offset(c.cell, d)
		if not _can_stand(c, to, player_cell, -1):
			continue
		var nd: int = Cells.manhattan_2d(to, player_cell)
		if nd > best_d:
			best_d = nd
			best = [to]
		elif nd == best_d and nd > dist:
			best.append(to)
	if best.is_empty():
		# Cornered: it faces the hero, trembling.
		var before: Vector2i = c.facing
		face(c, player_cell)
		return {"turned": c.facing != before}
	var pick: Vector3i = best[int(_roll(c, "flee") * best.size()) % best.size()]
	_move(c, pick)
	return {"moved": true}


func _step_patrol(c: WildCreature, player_cell: Vector3i, allow_contact: bool) -> Dictionary:
	var pts: Array[Vector2i] = c.entry.patrol
	var n: int = pts.size()
	c.waypoint = posmod(c.waypoint, n)
	if Vector2i(c.cell.x, c.cell.y) == pts[c.waypoint]:
		c.waypoint = (c.waypoint + 1) % n
	var target: Vector2i = pts[c.waypoint]
	var d := Vector2i.ZERO
	if target.x != c.cell.x:
		d = Vector2i(signi(target.x - c.cell.x), 0)
	elif target.y != c.cell.y:
		d = Vector2i(0, signi(target.y - c.cell.y))
	if d == Vector2i.ZERO:
		return {}
	var to := _offset(c.cell, d)
	if to == player_cell:
		c.facing = d
		return {"contact": allow_contact, "turned": true}
	# A patrol route is authored: it may leave the zone (leash off), never walk through walls.
	if _can_stand(c, to, player_cell, -1, false):
		_move(c, to)
		return {"moved": true}
	var turned: bool = c.facing != d
	c.facing = d
	return {"turned": turned}


func _move(c: WildCreature, to: Vector3i) -> void:
	var d := Vector2i(to.x - c.cell.x, to.y - c.cell.y)
	if d != Vector2i.ZERO:
		c.facing = d
	if grid != null:
		grid.clear_blocker(c.cell)
		grid.set_blocker(to, blocker_id(c.key))
	c.cell = to


## May [param c] stand on [param cell]? Walkable (its own blocker ignored), not the hero's cell,
## further than [param clearance] from the hero (-1 = no clearance rule), and -- with
## [param leashed] -- one of its zone's cells.
func _can_stand(c: WildCreature, cell: Vector3i, player_cell: Vector3i, clearance: int, leashed: bool = true) -> bool:
	if cell == player_cell:
		return false
	if grid == null or not grid.is_walkable(cell, blocker_id(c.key)):
		return false
	if clearance >= 0 and player_cell != Cells.INVALID and Cells.manhattan_2d(cell, player_cell) <= clearance:
		return false
	if leashed and not (_cell_set.get(c.zone_key, {}) as Dictionary).has(cell):
		return false
	return true


func _roll(c: WildCreature, what: String) -> float:
	return EncounterRoller.unit_float(state.rng_seed if state != null else 0,
		"%s|wild|%s|%d|%d|%s" % [area_id, c.zone_key, c.slot, state.steps if state != null else 0, what])


static func _offset(cell: Vector3i, d: Vector2i) -> Vector3i:
	return Vector3i(cell.x + d.x, cell.y + d.y, cell.z)


# =====================================================================================
#  Internals
# =====================================================================================

func _index_zones() -> void:
	_zones.clear()
	_zone_order.clear()
	_cells.clear()
	_cell_set.clear()
	if area == null:
		return
	var zs: Array[EncounterZone] = area.zones()
	for i in range(zs.size()):
		var z: EncounterZone = zs[i]
		if not z.is_visible_mode() or z.entries().is_empty():
			continue
		var zk: String = z.key(i)
		if _zones.has(zk):
			continue
		_zones[zk] = z
		_zone_order.append(zk)
		_cells[zk] = [] as Array[Vector3i]
		_cell_set[zk] = {}
	if _zone_order.is_empty() or grid == null:
		return
	# Cells that hold an entity (warps, triggers, NPCs, signs) are never a creature's home.
	var occupied: Dictionary = {}
	for e in area.entity_list():
		for c in e.cells():
			occupied[c] = true
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector3i(x, y, 0)
			if occupied.has(cell) or not grid.is_terrain_passable(cell):
				continue
			var tid: StringName = grid.tile_id_at(cell)
			for zk in _zone_order:
				if (_zones[zk] as EncounterZone).contains(cell, tid):
					(_cells[zk] as Array).append(cell)
					(_cell_set[zk] as Dictionary)[cell] = true


func _slot_count(zone: EncounterZone) -> int:
	return clampi(zone.max_active, 0, MAX_SLOTS)


func _renew_due(zone: EncounterZone, rec: Dictionary) -> bool:
	var mark: int = int(rec.get("mark", 0))
	match zone.respawn:
		EncounterZone.Respawn.ON_REST:
			return state.rests != mark
		EncounterZone.Respawn.EVERY_N_STEPS:
			return state.steps - mark >= maxi(1, zone.respawn_steps)
	return state.visit_serial != mark


func _mark_now(zone: EncounterZone) -> int:
	match zone.respawn:
		EncounterZone.Respawn.ON_REST:
			return state.rests
		EncounterZone.Respawn.EVERY_N_STEPS:
			return state.steps
	return state.visit_serial


## A brand-new creature for [param slot] of a roster [param epoch]: species from the weighted,
## condition-filtered pool, a cell away from the hero, a facing. Null when nothing can live there.
func _roll_slot(zk: String, zone: EncounterZone, epoch: int, slot: int, player_cell: Vector3i) -> WildCreature:
	var pool: Array[EncounterEntry] = []
	var total: float = 0.0
	for e in zone.entries():
		if e.weight <= 0.0 or CharacterLibrary.get_character(e.character_id) == null:
			continue
		if not ConditionContext.evaluate(e.condition, state):
			continue
		pool.append(e)
		total += e.weight
	if pool.is_empty() or total <= 0.0:
		return null
	var pick: float = _spawn_float(zk, epoch, slot, "pick") * total
	var entry: EncounterEntry = pool[pool.size() - 1]
	var acc: float = 0.0
	for e in pool:
		acc += e.weight
		if pick < acc:
			entry = e
			break
	var at: Vector3i = _pick_cell(zk, zone, epoch, slot, player_cell, "spawn", entry)
	if at == Cells.INVALID:
		return null
	var c := WildCreature.new()
	c.zone_key = zk
	c.zone = zone
	c.slot = slot
	c.key = "%s#%d" % [zk, slot]
	c.entry = entry
	c.cell = at
	c.facing = DIRS[int(_spawn_float(zk, epoch, slot, "facing") * 4.0) % 4]
	c.waypoint = 0
	c.level = Progression.level_in_band(zone.band_in(area), _spawn_float(zk, epoch, slot, "level"))
	return c


func _restore_slot(zk: String, zone: EncounterZone, slot: int, raw) -> WildCreature:
	if not (raw is Dictionary) or slot < 0 or slot >= _slot_count(zone):
		return null
	var entry: EncounterEntry = zone.entry_for(String(raw.get("cid", "")))
	if entry == null or CharacterLibrary.get_character(entry.character_id) == null:
		return null
	var cell: Vector3i = Cells.from_variant(raw.get("cell", null))
	var c := WildCreature.new()
	c.zone_key = zk
	c.zone = zone
	c.slot = slot
	c.key = "%s#%d" % [zk, slot]
	c.entry = entry
	c.cell = cell if cell != Cells.INVALID else Vector3i(-1, -1, 0)
	c.facing = OverworldEntity.facing_vector(String(raw.get("facing", "south")))
	c.waypoint = maxi(0, int(raw.get("wp", 0)))
	c.level = maxi(0, int(raw.get("lv", 0)))
	if c.level <= 0:
		# A save from before levels: roll one for the creature already standing there.
		c.level = EncounterRoller.roll_level(state.rng_seed if state != null else 0,
			"%s|wild|%s|s%d|restored" % [area_id, zk, slot], zone.band_in(area))
	return c


## A free cell of the zone for [param slot] (deterministic in [param salt]): a patrol starts on one
## of its waypoints when it can; otherwise a hashed pick among the zone's free cells beyond the
## spawn clearance (relaxed when the zone is too small for it). INVALID when the zone is full.
func _pick_cell(zk: String, zone: EncounterZone, epoch: int, slot: int, player_cell: Vector3i,
		salt: String, entry: EncounterEntry) -> Vector3i:
	var probe := WildCreature.new()
	probe.zone_key = zk
	probe.key = "%s#%d" % [zk, slot]
	if entry != null and entry.patrols():
		var n: int = entry.patrol.size()
		for i in range(n):
			var wp: Vector2i = entry.patrol[(slot + i) % n]
			var cell := Vector3i(wp.x, wp.y, 0)
			if _free_for_spawn(probe, cell, player_cell, zone.spawn_clearance, false):
				return cell
	for clearance in [zone.spawn_clearance, 0]:
		var free: Array[Vector3i] = []
		for cell in _cells.get(zk, []):
			if _free_for_spawn(probe, cell, player_cell, int(clearance), true):
				free.append(cell)
		if not free.is_empty():
			var i: int = int(_spawn_float(zk, epoch, slot, "cell|" + salt) * free.size()) % free.size()
			return free[i]
	return Cells.INVALID


func _free_for_spawn(probe: WildCreature, cell: Vector3i, player_cell: Vector3i, clearance: int, leashed: bool) -> bool:
	if not _can_stand(probe, cell, player_cell, clearance, leashed):
		return false
	return creature_at(cell) == null


func _spawn_float(zk: String, epoch: int, slot: int, what: String) -> float:
	return EncounterRoller.unit_float(state.rng_seed, "%s|wild|%s|e%d|s%d|%s" % [area_id, zk, epoch, slot, what])


func _adopt(c: WildCreature) -> void:
	creatures.append(c)
	if grid != null:
		grid.set_blocker(c.cell, blocker_id(c.key))
	_sort_creatures()


func _sort_creatures() -> void:
	var order: Dictionary = {}
	for i in range(_zone_order.size()):
		order[_zone_order[i]] = i
	creatures.sort_custom(func(a: WildCreature, b: WildCreature) -> bool:
		var za: int = int(order.get(a.zone_key, 0))
		var zb: int = int(order.get(b.zone_key, 0))
		if za != zb:
			return za < zb
		return a.slot < b.slot)


## Write every live creature back into its zone record (JSON-ready: cells as arrays).
func _persist_all() -> void:
	if state == null:
		return
	var by_zone: Dictionary = {}
	for zk in _zone_order:
		by_zone[zk] = {}
	for c in creatures:
		(by_zone[c.zone_key] as Dictionary)[str(c.slot)] = {
			"cid": c.character_id(),
			"cell": Cells.to_array(c.cell),
			"facing": OverworldEntity.facing_name(c.facing),
			"wp": c.waypoint,
		}
		if c.level > 0:
			(by_zone[c.zone_key] as Dictionary)[str(c.slot)]["lv"] = c.level
	for zk in _zone_order:
		var rkey: String = record_key(area_id, zk)
		var rec: Dictionary = state.wild.get(rkey, {})
		if rec.is_empty():
			continue
		rec["slots"] = by_zone[zk]
		state.wild[rkey] = rec


static func _sorted_slot_keys(slots: Dictionary) -> Array:
	var keys: Array = slots.keys()
	keys.sort_custom(func(a, b) -> bool: return int(String(a)) < int(String(b)))
	return keys


# =====================================================================================
#  Save data
# =====================================================================================

## The saved "wild" zones block, coerced (CONQUEST.md rules 3 / 8): anything malformed is dropped,
## never raised -- an older save simply has none (every zone rolls a fresh roster).
static func sanitize_saved(raw) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for k in raw:
		var key: String = String(k)
		var rec = raw[k]
		if not key.contains("|") or not (rec is Dictionary):
			continue
		var slots_out: Dictionary = {}
		var slots = rec.get("slots", {})
		if slots is Dictionary:
			for sk in slots:
				var s: String = String(sk)
				if not s.is_valid_int() or int(s) < 0 or int(s) >= MAX_SLOTS:
					continue
				var v = slots[sk]
				if not (v is Dictionary):
					continue
				var cid: String = String(v.get("cid", ""))
				var cell: Vector3i = Cells.from_variant(v.get("cell", null))
				if cid.is_empty() or cell == Cells.INVALID:
					continue
				var f: String = String(v.get("facing", "south"))
				slots_out[str(int(s))] = {
					"cid": cid,
					"cell": Cells.to_array(cell),
					"facing": f if StoryState.FACING_NAMES.has(f) else "south",
					"wp": maxi(0, int(v.get("wp", 0))),
				}
				if int(v.get("lv", 0)) > 0:
					slots_out[str(int(s))]["lv"] = int(v.get("lv", 0))
		out[key] = {
			"epoch": maxi(0, int(rec.get("epoch", 0))),
			"mark": int(rec.get("mark", 0)),
			"visit": int(rec.get("visit", -1)),
			"slots": slots_out,
		}
	return out
