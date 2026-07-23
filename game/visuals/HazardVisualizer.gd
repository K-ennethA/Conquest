extends Node3D

class_name HazardVisualizer

# On-map 3D visuals for the two nature hazards that were previously INVISIBLE:
#
#   A. FOREST BARRAGE (Eldroot's traveling lane vine) -- a [TravelingHazard] that
#      crawls one band forward per turn. HazardManager emits, on GameEvents:
#        hazard_advanced(hazard, cells, next_cells, damage)
#        hazard_expired(hazard)
#      We render a solid, twisted low-poly VINE erupting on every current-band cell
#      (`cells`) and a fainter translucent TELEGRAPH glow on the band it will sweep
#      NEXT (`next_cells`), so the player can read the lane and step out. Keyed per
#      hazard instance id (several vines can travel at once); freed on expiry.
#
#   B. VINE TRAP (Petalfang's `vine_trap` TILE EFFECT) -- a persistent snare sitting
#      on a tile. Detected exactly like TileEffectOverlay: a full sweep on
#      CombatServices.board_ready and a single-cell rebuild on
#      CombatServices.tile_effects_changed(cell), reading CombatServices.tile_effects_at(cell)
#      for any effect whose `.id == &"vine_trap"`. We drop a distinctive coiled thorny
#      knot on those cells and remove it when the effect leaves.
#
# Pure additive Node3D overlay (mounted in GameWorld.tscn beside the other
# visualizers). Null-safe throughout so a headless / minimal scene with no
# GameEvents / CombatServices / GameSettings never crashes. Meshes and materials
# are shared resources reused across every instance; nodes are freed on
# expiry/removal so nothing leaks. Honors GameSettings.animations_on() -- when
# animations are off the vine/trap still appear, only the grow/pulse is skipped.

# Grid <-> world. A cell Vector2i(col,row) centers at
# GRID.calculate_map_position(Vector3(col, 0, row)); cell_size is 2 so the center
# is (col*2+1, 0, row*2+1). Meshes float just above the tile top (~y 0.1-0.2).
const GRID := preload("res://board/Grid.tres")

const VINE_BASE_Y := 0.15        # foot of a solid vine above the tile
const TELEGRAPH_Y := 0.13        # foot of the ghost telegraph
const TRAP_Y := 0.16             # foot of a trap coil
const PULSE_SPEED := 2.4         # radians/sec for the idle telegraph/trap pulse

# hazard instance id (int) -> container Node3D holding that vine's current-band +
# telegraph meshes. One entry per live hazard so simultaneous vines stay separate.
var _hazard_visuals: Dictionary = {}

# cell (Vector2i) -> trap marker Node3D. Persistent until the effect leaves.
var _trap_markers: Dictionary = {}

var _time: float = 0.0

# --- Shared, reused mesh/material resources (built once in _ready) ------------
var _seg_mesh_0: PrismMesh          # thick faceted base segment
var _seg_mesh_1: PrismMesh          # mid segment
var _seg_mesh_2: PrismMesh          # thin tip segment
var _thorn_mesh: PrismMesh          # small angular thorn / spike
var _leaf_mesh: PrismMesh           # flat leaf
var _telegraph_quad_mesh: PlaneMesh # flat ground glow footprint
var _coil_mesh: TorusMesh           # trap snare ring

var _vine_mat: StandardMaterial3D       # mossy green tendril
var _vine_dark_mat: StandardMaterial3D  # darker base of the vine
var _thorn_mat: StandardMaterial3D      # pale thorn accent
var _leaf_mat: StandardMaterial3D       # brighter leaf green
var _telegraph_mat: StandardMaterial3D  # translucent green glow (telegraph)
var _trap_coil_mat: StandardMaterial3D  # dark coil, faintly glowing
var _trap_thorn_mat: StandardMaterial3D # trap spike accent


func _ready() -> void:
	name = "HazardVisualizer"
	_build_shared_resources()

	# A. Traveling vine -- GameEvents seam (guard every autoload/signal).
	if GameEvents != null:
		if GameEvents.has_signal(&"hazard_advanced") \
				and not GameEvents.hazard_advanced.is_connected(_on_hazard_advanced):
			GameEvents.hazard_advanced.connect(_on_hazard_advanced)
		if GameEvents.has_signal(&"hazard_expired") \
				and not GameEvents.hazard_expired.is_connected(_on_hazard_expired):
			GameEvents.hazard_expired.connect(_on_hazard_expired)

	# B. Vine trap -- CombatServices seam, mirroring TileEffectOverlay.
	if CombatServices != null:
		if not CombatServices.board_ready.is_connected(_on_board_ready):
			CombatServices.board_ready.connect(_on_board_ready)
		if not CombatServices.tile_effects_changed.is_connected(_on_tile_effects_changed):
			CombatServices.tile_effects_changed.connect(_on_tile_effects_changed)

	# The board may already be up (board_ready could have fired before we connected).
	_rebuild_all_traps()


func _process(delta: float) -> void:
	_time += delta
	if not _anim_on():
		return
	# Idle pulse: the telegraph shimmers and the trap coil breathes + slowly turns
	# so both read as "active / dangerous". Shared materials, so this is cheap.
	var t: float = (sin(_time * PULSE_SPEED) + 1.0) * 0.5
	if _telegraph_mat != null:
		_telegraph_mat.emission_energy_multiplier = lerpf(0.35, 1.1, t)
	if _trap_coil_mat != null:
		_trap_coil_mat.emission_energy_multiplier = lerpf(0.3, 0.9, t)
	var breathe: float = 1.0 + 0.06 * sin(_time * PULSE_SPEED)
	for m in _trap_markers.values():
		if m != null and is_instance_valid(m):
			var marker: Node3D = m
			marker.rotation.y += delta * 0.4
			marker.scale = Vector3(breathe, breathe, breathe)


# --- Presentation helpers (null-safe GameSettings) ---------------------------

func _anim_on() -> bool:
	if GameSettings != null and GameSettings.has_method("animations_on"):
		return bool(GameSettings.animations_on())
	return true


## Scale an authored duration by the current speed setting; falls back to the base
## when GameSettings is absent or returns a non-positive value.
func _dur(base: float) -> float:
	if GameSettings != null and GameSettings.has_method("scaled_time"):
		var s: float = GameSettings.scaled_time(base)
		if s > 0.0:
			return s
	return base


# === A. Traveling vine (Forest Barrage) ======================================

func _on_hazard_advanced(hazard, cells, next_cells, _damage) -> void:
	if hazard == null:
		return
	var hid: int = hazard.get_instance_id()

	var container: Node3D = _hazard_visuals.get(hid, null)
	if container == null or not is_instance_valid(container):
		container = Node3D.new()
		container.name = "Vine_%d" % hid
		add_child(container)
		_hazard_visuals[hid] = container

	# The vine MOVED: drop the previous band + telegraph, then rebuild both so the
	# current band is always solid and the next band always telegraphed.
	_clear_children(container)

	var current := Node3D.new()
	current.name = "Current"
	container.add_child(current)

	var telegraph := Node3D.new()
	telegraph.name = "Telegraph"
	container.add_child(telegraph)

	# Solid vines on every current-band cell.
	if cells is Array:
		for cell in cells:
			var c: Vector2i = cell
			var vine := _make_vine()
			var center: Vector3 = GRID.calculate_map_position(Vector3(c.x, 0, c.y))
			vine.position = Vector3(center.x, VINE_BASE_Y, center.z)
			vine.rotation.y = randf() * TAU  # per-instance twist so they aren't clones
			current.add_child(vine)

	# Faint translucent telegraph on the band it will sweep next turn.
	if next_cells is Array:
		for cell2 in next_cells:
			var nc: Vector2i = cell2
			var ghost := _make_telegraph()
			var center2: Vector3 = GRID.calculate_map_position(Vector3(nc.x, 0, nc.y))
			ghost.position = Vector3(center2.x, TELEGRAPH_Y, center2.z)
			telegraph.add_child(ghost)

	# Grow/uncoil the fresh current band from the ground so it reads as crawling in.
	if _anim_on():
		current.scale = Vector3(1.0, 0.01, 1.0)
		var tw := create_tween()
		tw.tween_property(current, "scale", Vector3.ONE, _dur(0.35)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_hazard_expired(hazard) -> void:
	if hazard == null:
		return
	var hid: int = hazard.get_instance_id()
	var container: Node3D = _hazard_visuals.get(hid, null)
	_hazard_visuals.erase(hid)
	if container == null or not is_instance_valid(container):
		return
	if _anim_on():
		var tw := create_tween()
		tw.tween_property(container, "scale", Vector3(1.0, 0.01, 1.0), _dur(0.3)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(container.queue_free)
	else:
		container.queue_free()


# === B. Vine trap marker =====================================================

func _on_board_ready() -> void:
	_rebuild_all_traps()


func _on_tile_effects_changed(cell: Vector2i) -> void:
	_rebuild_trap_cell(cell)


## Full sweep: clear every trap marker, then place one on any cell that currently
## carries the `vine_trap` effect. Mirrors TileEffectOverlay._rebuild_all.
func _rebuild_all_traps() -> void:
	for cell in _trap_markers.keys():
		var m = _trap_markers[cell]
		if m != null and is_instance_valid(m):
			m.queue_free()
	_trap_markers.clear()

	if CombatServices == null:
		return
	var cols: int = int(GRID.size.x)
	var rows: int = int(GRID.size.z)
	for col in range(cols):
		for row in range(rows):
			var cell := Vector2i(col, row)
			if _cell_has_trap(cell):
				_place_trap(cell)


## Single-cell reconcile: add a marker if the trap just appeared, remove it if the
## trap is gone, otherwise leave the existing marker in place.
func _rebuild_trap_cell(cell: Vector2i) -> void:
	var has_trap: bool = _cell_has_trap(cell)
	var existing = _trap_markers.get(cell, null)
	var existing_valid: bool = existing != null and is_instance_valid(existing)
	if has_trap and not existing_valid:
		_place_trap(cell)
	elif not has_trap and existing != null:
		if existing_valid:
			existing.queue_free()
		_trap_markers.erase(cell)


func _cell_has_trap(cell: Vector2i) -> bool:
	if CombatServices == null:
		return false
	var effects: Array = CombatServices.tile_effects_at(cell)
	for fx in effects:
		if fx != null and fx.id == &"vine_trap":
			return true
	return false


func _place_trap(cell: Vector2i) -> void:
	var center: Vector3 = GRID.calculate_map_position(Vector3(cell.x, 0, cell.y))
	var trap := _make_trap()
	trap.position = Vector3(center.x, TRAP_Y, center.z)
	add_child(trap)
	_trap_markers[cell] = trap

	if _anim_on():
		trap.scale = Vector3(0.01, 0.01, 0.01)
		var tw := create_tween()
		tw.tween_property(trap, "scale", Vector3.ONE, _dur(0.3)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# === Procedural mesh construction ============================================

func _build_shared_resources() -> void:
	# Faceted, tapering triangular-prism segments -- stacked + twisted they read as
	# an angular low-poly tendril.
	_seg_mesh_0 = PrismMesh.new()
	_seg_mesh_0.size = Vector3(0.28, 0.26, 0.28)
	_seg_mesh_1 = PrismMesh.new()
	_seg_mesh_1.size = Vector3(0.20, 0.24, 0.20)
	_seg_mesh_2 = PrismMesh.new()
	_seg_mesh_2.size = Vector3(0.12, 0.24, 0.12)

	_thorn_mesh = PrismMesh.new()
	_thorn_mesh.size = Vector3(0.06, 0.16, 0.06)

	_leaf_mesh = PrismMesh.new()
	_leaf_mesh.size = Vector3(0.18, 0.02, 0.12)

	_telegraph_quad_mesh = PlaneMesh.new()
	_telegraph_quad_mesh.size = Vector2(1.6, 1.6)
	_telegraph_quad_mesh.orientation = PlaneMesh.FACE_Y

	# A BIG green ring that nearly fills the 2-unit tile, so a laid trap reads at a glance
	# (was a tiny 0.36-radius coil that was easy to miss).
	_coil_mesh = TorusMesh.new()
	_coil_mesh.inner_radius = 0.6
	_coil_mesh.outer_radius = 0.92
	_coil_mesh.rings = 4          # low poly -> chunky faceted ring
	_coil_mesh.ring_segments = 14

	# Mossy palette: a couple of greens, a dark base, a pale thorn accent.
	_vine_mat = _lit_mat(Color(0.22, 0.5, 0.18))
	_vine_dark_mat = _lit_mat(Color(0.1, 0.28, 0.1))
	_thorn_mat = _lit_mat(Color(0.62, 0.62, 0.28))
	_leaf_mat = _lit_mat(Color(0.3, 0.62, 0.22))

	# Trap: a bright green ring that glows (pulsed in _process) so the big torus is
	# unmistakable on the board + a brighter spike.
	_trap_coil_mat = _lit_mat(Color(0.24, 0.68, 0.26))
	_trap_coil_mat.emission_enabled = true
	_trap_coil_mat.emission = Color(0.35, 0.95, 0.4)
	_trap_coil_mat.emission_energy_multiplier = 1.1
	_trap_thorn_mat = _lit_mat(Color(0.6, 0.6, 0.25))

	# Telegraph: translucent, unshaded, glowing green -- clearly fainter/flatter than
	# the solid current-band vine, so "here now" vs "here next" never blur together.
	_telegraph_mat = StandardMaterial3D.new()
	_telegraph_mat.albedo_color = Color(0.35, 0.85, 0.4, 0.26)
	_telegraph_mat.flags_unshaded = true
	_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_telegraph_mat.emission_enabled = true
	_telegraph_mat.emission = Color(0.4, 0.9, 0.45)
	_telegraph_mat.emission_energy_multiplier = 0.7
	_telegraph_mat.flags_do_not_receive_shadows = true
	_telegraph_mat.render_priority = 2


## Flat-ish lit material for the low-poly vine/trap look (rough, non-metallic).
func _lit_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


## A solid, twisted low-poly vine: three tapering faceted segments stacked and
## progressively rotated, with a thorn and a leaf near the tip.
func _make_vine() -> Node3D:
	var v := Node3D.new()
	v.add_child(_seg(_seg_mesh_0, _vine_dark_mat, Vector3(0.0, 0.13, 0.0), 0.0))
	v.add_child(_seg(_seg_mesh_1, _vine_mat, Vector3(0.03, 0.37, 0.02), 0.7))
	v.add_child(_seg(_seg_mesh_2, _vine_mat, Vector3(0.06, 0.58, 0.05), 1.4))

	var thorn := _mi(_thorn_mesh, _thorn_mat)
	thorn.position = Vector3(0.1, 0.42, 0.0)
	thorn.rotation = Vector3(0.0, 0.0, -1.2)
	v.add_child(thorn)

	var leaf := _mi(_leaf_mesh, _leaf_mat)
	leaf.position = Vector3(-0.02, 0.66, 0.06)
	leaf.rotation = Vector3(0.5, 0.8, 0.2)
	v.add_child(leaf)
	return v


## A faint telegraph: a flat translucent glow footprint on the ground plus a short
## ghostly tendril, so the player sees where the vine sweeps NEXT turn.
func _make_telegraph() -> Node3D:
	var g := Node3D.new()

	var footprint := _mi(_telegraph_quad_mesh, _telegraph_mat)
	footprint.position = Vector3(0.0, 0.02, 0.0)
	g.add_child(footprint)

	var ghost := _mi(_seg_mesh_1, _telegraph_mat)
	ghost.position = Vector3(0.0, 0.22, 0.0)
	ghost.scale = Vector3(0.6, 1.1, 0.6)
	g.add_child(ghost)
	return g


## A coiled thorny snare knot: a flattened faceted ring ringed with outward spikes,
## visually unlike the generic terrain pip so a trap reads instantly.
func _make_trap() -> Node3D:
	var t := Node3D.new()

	var coil := _mi(_coil_mesh, _trap_coil_mat)
	coil.scale = Vector3(1.0, 0.55, 1.0)  # flatten into a low coil
	t.add_child(coil)

	# Spikes ride ON the big ring (radius ~0.76), not inside its hole.
	var spikes: int = 8
	for i in range(spikes):
		var a: float = float(i) / float(spikes) * TAU
		var spike := _mi(_thorn_mesh, _trap_thorn_mat)
		spike.position = Vector3(cos(a) * 0.76, 0.06, sin(a) * 0.76)
		spike.rotation = Vector3(cos(a) * 0.6, -a, sin(a) * 0.6)  # tilt outward
		t.add_child(spike)
	return t


## Shared-mesh MeshInstance3D with shadows off.
func _mi(mesh: Mesh, mat: StandardMaterial3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## A vine segment: a shared prism mesh, twisted around Y and slightly tilted so the
## stack curls rather than standing perfectly straight.
func _seg(mesh: Mesh, mat: StandardMaterial3D, pos: Vector3, twist: float) -> MeshInstance3D:
	var m := _mi(mesh, mat)
	m.position = pos
	m.rotation = Vector3(0.08, twist, 0.06)
	return m


## Free all children of [param node] (used to drop a vine's previous band before
## rebuilding). queue_free is deferred; freshly added children are unaffected.
func _clear_children(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()
