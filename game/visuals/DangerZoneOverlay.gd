extends Node3D
class_name DangerZoneOverlay

## Fire Emblem's DANGER ZONE: a toggle (action `danger_zone`, default Z / gamepad
## L3, see InputActions) that paints every cell any hostile unit could strike
## on its next turn, in translucent purple, on each cell's own floor.
##
## The cells come from [method ThreatResolver.combined_threat] over every living
## unit not owned by the local viewer ([LocalPlayer.viewer]). While active the zone
## is recomputed (coalesced to once per frame) whenever the board changes: a unit
## moved / died / spawned, a turn started, or the board was rebuilt. While hidden it
## only marks itself dirty, so it costs nothing until shown.

const ZONE_COLOR := Color(0.62, 0.12, 0.95, 0.46)
## Just under the blue move range (0.16) so both read where they overlap.
const ZONE_HEIGHT := 0.13

var active: bool = false

var _pool: CellOverlayPool
var _cells: Array[Vector3i] = []
var _recompute_queued: bool = false
var _watched_ts = null

# Per-unit threat cache: unit -> { "cell": Vector3i, "reach": int, "attack": Array }.
# A unit is recomputed only when it moved, or when a cell whose occupancy changed
# lies within its movement reach (+1); everything else reuses its last answer. A
# turn start / board rebuild / toggle-on clears the cache (cooldowns, spawns).
var _cache: Dictionary = {}
var _changed_cells: Array[Vector3i] = []


func _ready() -> void:
	name = "DangerZoneOverlay"
	add_to_group(&"danger_zone_overlay")
	_pool = CellOverlayPool.new(self, CellOverlayPool.make_material(ZONE_COLOR, 0.5, -1), ZONE_HEIGHT, "DangerZoneCell")
	if GameEvents:
		GameEvents.unit_moved.connect(_on_unit_moved)
		GameEvents.unit_eliminated.connect(_on_unit_gone)
		GameEvents.unit_spawned.connect(func(_u, _r): _invalidate_all())
	var services := get_node_or_null("/root/CombatServices")
	if services != null and services.has_signal("board_ready"):
		services.board_ready.connect(_invalidate_all)
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_watch_turn_system)
		if TurnSystemManager.has_active_turn_system():
			_watch_turn_system(TurnSystemManager.get_active_turn_system())


func _watch_turn_system(ts) -> void:
	if ts == _watched_ts:
		return
	if _watched_ts != null and is_instance_valid(_watched_ts) and _watched_ts.turn_started.is_connected(_on_turn_started):
		_watched_ts.turn_started.disconnect(_on_turn_started)
	_watched_ts = ts
	if ts != null and not ts.turn_started.is_connected(_on_turn_started):
		ts.turn_started.connect(_on_turn_started)


func _on_turn_started(_player) -> void:
	_invalidate_all()


func _on_unit_moved(_unit, from_pos, to_pos) -> void:
	if not active:
		return  # toggling on rebuilds from scratch
	if from_pos is Vector3:
		_changed_cells.append(Cells.from_grid(from_pos))
	if to_pos is Vector3:
		_changed_cells.append(Cells.from_grid(to_pos))
	_mark_dirty()


func _on_unit_gone(unit, _eliminator = null) -> void:
	if _cache.has(unit):
		_changed_cells.append(_cache[unit]["cell"])
		_cache.erase(unit)
	_mark_dirty()


func _invalidate_all(_a = null) -> void:
	_cache.clear()
	_changed_cells.clear()
	_mark_dirty()


func _unhandled_input(event: InputEvent) -> void:
	if InputActions.gameplay_input_blocked(get_tree()):
		return
	if event.is_action_pressed(InputActions.DANGER_ZONE):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	set_active(not active)


func set_active(on: bool) -> void:
	active = on
	if active:
		_cache.clear()
		_changed_cells.clear()
		recompute()
	else:
		_pool.clear()
		_cells.clear()
		if GameEvents:
			GameEvents.danger_zone_changed.emit(false, 0)


## Threatened cells currently shown (Vector3i board cells).
func get_cells() -> Array[Vector3i]:
	return _cells.duplicate()


## Recompute and redraw now (no-op while hidden).
func recompute() -> void:
	_recompute_queued = false
	if not active:
		return
	var board = CombatServices.board() if CombatServices else null
	_cells.clear()
	if board != null:
		var viewer := LocalPlayer.viewer()
		var hostile := ThreatResolver.hostile_units(board, func(u): return _is_hostile(u, viewer))
		var snap = BoardSnapshot.of(board)
		var alive := {}
		var union := {}
		for u in hostile:
			alive[u] = true
			var cell: Vector3i = snap.cell_of(u)
			var entry = _cache.get(u)
			if entry == null or entry["cell"] != cell or _touched(cell, int(entry["reach"])):
				var profile = u.get_movement_profile() if u.has_method("get_movement_profile") else null
				entry = {
					"cell": cell,
					"reach": (int(profile.range) if profile != null else 0) + 1,
					"attack": ThreatResolver.unit_threat(u, snap)["attack"],
				}
				_cache[u] = entry
			for c in entry["attack"]:
				union[c] = true
		for u in _cache.keys():
			if not alive.has(u):
				_cache.erase(u)
		for c in union.keys():
			_cells.append(c)
		_cells.sort_custom(Cells.less)
	_changed_cells.clear()
	_pool.show_cells(_cells)
	if GameEvents:
		GameEvents.danger_zone_changed.emit(true, _cells.size())


## True when an occupancy change since the last recompute lies within [param reach]
## of [param cell] (so that unit's flood may route differently now).
func _touched(cell: Vector3i, reach: int) -> bool:
	for c in _changed_cells:
		if Cells.distance(c, cell) <= reach:
			return true
	return false


func _mark_dirty(_a = null) -> void:
	if not active or _recompute_queued:
		return
	_recompute_queued = true
	recompute.call_deferred()


## Hostile = owned by someone other than the viewer (neutral camps included). With
## no local viewer (an all-AI match) nothing counts as hostile.
static func _is_hostile(unit, viewer: Player) -> bool:
	if viewer == null:
		return false
	var owner := LocalPlayer.owner_of(unit)
	return owner != viewer
