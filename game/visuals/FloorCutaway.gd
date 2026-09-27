extends Node
class_name FloorCutaway

## Multi-floor CUTAWAY: turns every floor above the cut floor (tiles, stair / edge
## decor, and the units standing up there) into a faint translucent "ghost", and
## hides those units' HP bars, so units under a bridge or inside a castle stay
## readable.
##
## Driven entirely by [signal GameEvents.view_floor_changed] (the board cursor owns
## the view floor; see board/cursor/cursor.gd + FloorNav). Nothing happens on a
## single-floor map.
##
## How: each cut floor gets ONE shared translucent ghost material. Cutting a floor
## swaps it in as material_override on that floor's geometry (remembering the
## previous override / overlay / shadow setting in node meta) and tweens the ghost's
## alpha down; restoring tweens it back up and swaps the originals back. So the
## per-frame cost during a fade is a single material property, and zero otherwise.
## (Material swapping is used rather than GeometryInstance3D.transparency because
## the latter is ignored by the Compatibility renderer.)
##
## LOCAL fade: independent of the view floor, the few upper-floor deck cells that
## hide the board cursor or the selected unit on screen are ghosted individually
## (lighter ghost, same material trick): the cell directly above, and -- because
## the battle camera looks from the south (+row) -- the cells one row further
## south per floor of height difference. So a unit just north of a bridge or
## behind a rampart stays readable without cutting the whole floor away.

## Ghost alpha of a fully cut-away floor, and where the fade starts / ends.
const GHOST_ALPHA := 0.09
## Ghost alpha of a single deck cell faded because it hides the cursor / selection.
const LOCAL_GHOST_ALPHA := 0.22
const GHOST_ALPHA_START := 0.6
## Seconds a floor takes to fade out / back in.
const FADE_TIME := 0.18
const GHOST_COLOR := Color(0.7, 0.76, 0.88)

const META_OVERRIDE := &"_cutaway_prev_override"
const META_OVERLAY := &"_cutaway_prev_overlay"
const META_SHADOW := &"_cutaway_prev_shadow"
const META_VISIBLE := &"_cutaway_prev_visible"

var _floor_count: int = 1
var _cut_floor: int = 0
## floor -> true while that floor is ghosted (or fading out).
var _cut: Dictionary = {}
## floor -> StandardMaterial3D ghost
var _ghost: Dictionary = {}
## floor -> Tween
var _tweens: Dictionary = {}
## floor -> Array[Node] (tile + decor geometry), rebuilt on board_ready.
var _geo_cache: Dictionary = {}
## Unit -> floor it was ghosted on.
var _ghost_units: Dictionary = {}
## Locally ghosted upper cells (Vector3i -> true) and their shared material.
var _local: Dictionary = {}
var _local_mat: StandardMaterial3D = null
## Cells the local fade keeps clear: the cursor and the selected unit.
var _cursor_cell: Vector3i = Cells.INVALID
var _selected_unit: Node3D = null


func _ready() -> void:
	name = "FloorCutaway"
	add_to_group("floor_cutaway")
	if GameEvents and GameEvents.has_signal("view_floor_changed") \
			and not GameEvents.view_floor_changed.is_connected(_on_view_floor_changed):
		GameEvents.view_floor_changed.connect(_on_view_floor_changed)
	if GameEvents and not GameEvents.unit_moved.is_connected(_on_unit_moved):
		GameEvents.unit_moved.connect(_on_unit_moved)
	if GameEvents and GameEvents.has_signal("unit_spawned") \
			and not GameEvents.unit_spawned.is_connected(_on_unit_spawned):
		GameEvents.unit_spawned.connect(_on_unit_spawned)
	if CombatServices and not CombatServices.board_ready.is_connected(_on_board_ready):
		CombatServices.board_ready.connect(_on_board_ready)
	if GameEvents and not GameEvents.cursor_moved.is_connected(_on_cursor_moved):
		GameEvents.cursor_moved.connect(_on_cursor_moved)
	if GameEvents and not GameEvents.unit_selected.is_connected(_on_unit_selected):
		GameEvents.unit_selected.connect(_on_unit_selected)
	if GameEvents and not GameEvents.unit_deselected.is_connected(_on_unit_deselected):
		GameEvents.unit_deselected.connect(_on_unit_deselected)


## The floor currently cut to (floors above it are ghosted).
func get_cut_floor() -> int:
	return _cut_floor


## True while [param floor_index] is cut away (ghosted).
func is_floor_cut(floor_index: int) -> bool:
	return bool(_cut.get(floor_index, false))


func _on_board_ready() -> void:
	for t in _tweens.values():
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()
	_geo_cache.clear()
	_cut.clear()
	_ghost_units.clear()
	_local.clear()
	var board = CombatServices.board() if CombatServices else null
	_floor_count = int(board.floor_count()) if board != null and board.has_method("floor_count") else 1
	_cut_floor = _floor_count - 1


func _on_view_floor_changed(_view_floor: int, cut_floor: int, floor_count: int) -> void:
	_floor_count = maxi(1, floor_count)
	_cut_floor = clampi(cut_floor, 0, _floor_count - 1)
	for f in range(1, _floor_count):
		_set_floor_cut(f, f > _cut_floor)
	_apply_units()
	_update_local()


func _ghost_material(f: int) -> StandardMaterial3D:
	if _ghost.has(f):
		return _ghost[f]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(GHOST_COLOR, GHOST_ALPHA)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.render_priority = -1
	_ghost[f] = m
	return m


func _set_floor_cut(f: int, cut: bool) -> void:
	var was := bool(_cut.get(f, false))
	if was == cut:
		return
	_cut[f] = cut
	var mat := _ghost_material(f)
	var running: Tween = _tweens.get(f, null)
	if running != null and running.is_valid():
		running.kill()
	if cut:
		# The whole floor takes over from any locally ghosted cells on it.
		for c in _local.keys():
			if c.z == f:
				_local.erase(c)
		for n in _floor_geometry(f):
			_ghost_node(n, mat)
		mat.albedo_color.a = GHOST_ALPHA_START
		_tween_alpha(f, mat, GHOST_ALPHA, Callable())
	else:
		_tween_alpha(f, mat, GHOST_ALPHA_START, _restore_floor.bind(f))


func _tween_alpha(f: int, mat: StandardMaterial3D, target: float, done: Callable) -> void:
	if not is_inside_tree():
		mat.albedo_color.a = target
		if done.is_valid():
			done.call()
		return
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", target, FADE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if done.is_valid():
		tw.tween_callback(done)
	_tweens[f] = tw


func _restore_floor(f: int) -> void:
	if bool(_cut.get(f, false)):
		return  # re-cut while fading back in
	for n in _floor_geometry(f):
		_restore_node(n)
	_apply_units()
	_update_local()


## Ghost / restore every unit according to its CURRENT floor (units move).
func _apply_units() -> void:
	var board = CombatServices.board() if CombatServices else null
	if board == null:
		return
	var seen := {}
	for u in board.all_units():
		if u == null or not is_instance_valid(u) or not (u is Node3D):
			continue
		seen[u] = true
		var f: int = board.cell_of(u).z
		var want := bool(_cut.get(f, false))
		var cur_f: int = int(_ghost_units.get(u, -1))
		if want and cur_f == f:
			continue
		if cur_f >= 0:
			_unghost_unit(u)
		if want:
			_ghost_unit(u, f)
	for u in _ghost_units.keys():
		if not seen.has(u):
			_ghost_units.erase(u)


func _ghost_unit(unit: Node3D, f: int) -> void:
	_ghost_units[unit] = f
	for n in _unit_geometry(unit):
		_ghost_node(n, _ghost_material(f))


func _unghost_unit(unit: Node3D) -> void:
	_ghost_units.erase(unit)
	for n in _unit_geometry(unit):
		_restore_node(n)


## Swap [param n] to the ghost look, remembering what it had.
func _ghost_node(n: Node, mat: Material) -> void:
	if not is_instance_valid(n):
		return
	if n is Label3D or n is SpriteBase3D or n is HealthBar:
		if not n.has_meta(META_VISIBLE):
			n.set_meta(META_VISIBLE, n.visible)
		n.visible = false
		return
	if not (n is GeometryInstance3D):
		return
	var gi := n as GeometryInstance3D
	if not gi.has_meta(META_OVERRIDE):
		gi.set_meta(META_OVERRIDE, gi.material_override)
		gi.set_meta(META_OVERLAY, gi.material_overlay)
		gi.set_meta(META_SHADOW, gi.cast_shadow)
	gi.material_override = mat
	gi.material_overlay = null
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _restore_node(n: Node) -> void:
	if not is_instance_valid(n):
		return
	if n.has_meta(META_VISIBLE):
		n.visible = bool(n.get_meta(META_VISIBLE))
		n.remove_meta(META_VISIBLE)
		return
	if not (n is GeometryInstance3D) or not n.has_meta(META_OVERRIDE):
		return
	var gi := n as GeometryInstance3D
	# Only put the old material back if nobody replaced our ghost meanwhile.
	if gi.material_override is StandardMaterial3D and (_ghost.values().has(gi.material_override) \
			or gi.material_override == _local_mat):
		gi.material_override = gi.get_meta(META_OVERRIDE)
		gi.material_overlay = gi.get_meta(META_OVERLAY)
	gi.cast_shadow = gi.get_meta(META_SHADOW)
	gi.remove_meta(META_OVERRIDE)
	gi.remove_meta(META_OVERLAY)
	gi.remove_meta(META_SHADOW)


func _floor_geometry(f: int) -> Array:
	if _geo_cache.has(f):
		return _geo_cache[f]
	var out: Array = []
	var tiles := _tiles_root()
	if tiles != null:
		var container := tiles.get_node_or_null("Floor_%d" % f)
		if container != null:
			out = _collect(container)
		# FloorDecor: this floor's dressing, and the stairs / ladders reaching it.
		var decor := tiles.get_node_or_null("Decor/Floor_%d" % f)
		if decor != null:
			out.append_array(_collect(decor))
		var links := tiles.get_node_or_null("Links")
		if links != null:
			for l in links.get_children():
				if int(l.get_meta(&"cutaway_floor", -1)) == f:
					out.append_array(_collect(l))
	_geo_cache[f] = out
	return out


func _tiles_root() -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null("Map/Tiles")


## Geometry of a unit, with its HP bar (and labels) as whole nodes to hide.
static func _unit_geometry(unit: Node) -> Array:
	return _collect(unit)


## Every GeometryInstance3D under [param node]; HealthBar subtrees are returned as
## the single HealthBar node (hidden, not ghosted -- its billboards would break).
static func _collect(node: Node) -> Array:
	var out: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is HealthBar:
			out.append(n)
			continue
		if n is GeometryInstance3D:
			out.append(n)
		stack.append_array(n.get_children())
	return out


func _on_unit_moved(_unit, _from, _to) -> void:
	if _floor_count > 1:
		_apply_units()


func _on_unit_spawned(_unit, _runtime) -> void:
	if _floor_count > 1:
		call_deferred("_apply_units")


# --- Local fade (deck cells hiding the cursor / selected unit) --------------------

func _on_cursor_moved(grid_pos: Vector3) -> void:
	_cursor_cell = Cells.from_grid(grid_pos)
	if _floor_count > 1:
		_update_local()


func _on_unit_selected(unit, _world_pos) -> void:
	_selected_unit = unit if unit is Node3D else null
	if _floor_count > 1:
		_update_local()


func _on_unit_deselected(_unit) -> void:
	_selected_unit = null
	if _floor_count > 1:
		_update_local()


## The upper cells that hide [param c] on screen: directly above it, and one row
## further south (toward the camera) per floor of height difference.
static func occluders_of(board, c: Vector3i, floor_count: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if board == null or c == Cells.INVALID:
		return out
	for f in range(c.z + 1, floor_count):
		for k in range(0, f - c.z + 1):
			var cc := Vector3i(c.x, c.y + k, f)
			if board.has_tile(cc):
				out.append(cc)
	return out


func _update_local() -> void:
	var board = CombatServices.board() if CombatServices else null
	var want := {}
	if board != null and _floor_count > 1:
		var focus: Array[Vector3i] = [_cursor_cell]
		if _selected_unit != null and is_instance_valid(_selected_unit):
			focus.append(board.cell_of(_selected_unit))
		for c in focus:
			for cc in occluders_of(board, c, _floor_count):
				if not bool(_cut.get(cc.z, false)):
					want[cc] = true
	for cc in _local.keys():
		if not want.has(cc):
			_local.erase(cc)
			for n in _cell_geometry(cc):
				_restore_node(n)
	if want.is_empty():
		return
	if _local_mat == null:
		_local_mat = _ghost_material(-1).duplicate()
		_local_mat.albedo_color.a = LOCAL_GHOST_ALPHA
	for cc in want:
		if _local.has(cc):
			continue
		_local[cc] = true
		for n in _cell_geometry(cc):
			_ghost_node(n, _local_mat)


## Tile + decor geometry of one upper cell.
func _cell_geometry(cc: Vector3i) -> Array:
	var out: Array = []
	var tiles := _tiles_root()
	if tiles == null:
		return out
	for path in ["Floor_%d/Tile_%d_%d_%d" % [cc.z, cc.x, cc.y, cc.z], "Decor/Floor_%d/Decor_%d_%d" % [cc.z, cc.x, cc.y]]:
		var n := tiles.get_node_or_null(path)
		if n != null:
			out.append_array(_collect(n))
	return out
