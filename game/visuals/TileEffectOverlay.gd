extends Node3D

class_name TileEffectOverlay

# In-battle 3D map overlay for TILE EFFECTS. A tile can hold MULTIPLE effects at
# once (e.g. tall grass that grants evasion AND a fire a move ignited on top),
# so this floats a small horizontal ROW of billboarded colored "pips" just above
# each affected cell -- one pip per effect -- making both the presence AND the
# stacking count legible at a glance without repainting the terrain mesh.
#
# Colours come exclusively from [TileEffectVisuals] (the single source of truth
# shared with the TerrainInfoPanel chips) so the map and the panel always agree
# on what "Fire" looks like. Hazard pips gently pulse; buffs stay steady.
#
# Built reactively: a full pass on [signal CombatServices.board_ready] (covering
# BASE terrain effects -- lava->Fire, water->Empowering Water, etc.) and a cheap
# single-cell rebuild on [signal CombatServices.tile_effects_changed] (runtime
# ignite/douse). It is a pure additive [Node3D] overlay -- see
# [code]GameWorldManager._setup_tile_effect_overlay[/code], which adds it to the
# 3D scene root (not the "UI" CanvasLayer, unlike TerrainInfoPanel).

# Pip geometry. Small quads (< the X spacing) so a row of them never overlaps and
# the count reads cleanly. Floated at PIP_Y so they clear the ~0.2-tall tile tops.
const PIP_SIZE := 0.2
const PIP_SPACING := 0.22   # world units between adjacent pip centers along X
const PIP_Y := 0.55         # height above the cell center

# Hazard pulse: a slow sine varying alpha/emission so a "hazard" pip (Fire) reads
# as active/dangerous while buffs sit calm. Kept subtle -- not a strobe.
const PULSE_SPEED := 3.0                       # radians/sec
const PULSE_ALPHA := Vector2(0.55, 1.0)        # min..max albedo alpha
const PULSE_EMISSION := Vector2(0.15, 0.75)    # min..max emission energy

# cell (Vector2i) -> container Node3D holding that cell's pip row. Kept so a
# single cell can be rebuilt cheaply (free its old container, build a new one).
var _markers: Dictionary = {}

# Drives the shared pulse phase in _process.
var _pulse_time: float = 0.0


func _ready() -> void:
	name = "TileEffectOverlay"

	# React to the board lifecycle. board_ready fires after every map rebuild, so
	# we do a full pass then; tile_effects_changed fires for a single cell when a
	# move ignites/douses it, so we only restack that one cell.
	if CombatServices:
		if not CombatServices.board_ready.is_connected(_on_board_ready):
			CombatServices.board_ready.connect(_on_board_ready)
		if not CombatServices.tile_effects_changed.is_connected(_on_tile_effects_changed):
			CombatServices.tile_effects_changed.connect(_on_tile_effects_changed)

	# Attempt an initial pass in case the board is already up by the time we are
	# added (board_ready may have fired before we connected).
	_rebuild_all()


func _process(delta: float) -> void:
	_pulse_time += delta
	# Shared 0..1 pulse factor (sine, offset so it never fully vanishes).
	var t: float = (sin(_pulse_time * PULSE_SPEED) + 1.0) * 0.5
	var alpha: float = lerpf(PULSE_ALPHA.x, PULSE_ALPHA.y, t)
	var emission: float = lerpf(PULSE_EMISSION.x, PULSE_EMISSION.y, t)

	# Only hazard pips pulse; their materials are stashed on each container's meta
	# when it is built (buffs are omitted, so they stay steady).
	for container in _markers.values():
		if container == null or not is_instance_valid(container):
			continue
		var hazard_mats: Array = container.get_meta("hazard_mats", []) as Array
		for m in hazard_mats:
			if m is StandardMaterial3D:
				var mat: StandardMaterial3D = m
				mat.albedo_color.a = alpha
				mat.emission_energy_multiplier = emission


# --- Reactive rebuild --------------------------------------------------------

## Full rebuild across every cell: clear all markers, then (re)build a pip row for
## any cell whose merged effect list (base terrain + runtime) is non-empty. This
## is where BASE terrain effects first appear after a map loads.
func _rebuild_all() -> void:
	for cell in _markers.keys():
		var container = _markers[cell]
		if container != null and is_instance_valid(container):
			container.queue_free()
	_markers.clear()

	# GRID is a preloaded const (always available). Its `size` is a Vector3 where
	# X = columns and Z = rows (MapLoader sets it to Vector3(w, 0, h) per map), so
	# we sweep X for cols and Z for rows -- matching MovementVisualizer /
	# MapGridVisualizer, which read grid.size.x / grid.size.z the same way.
	if CombatServices == null:
		return
	var cols: int = int(CombatServices.GRID.size.x)
	var rows: int = int(CombatServices.GRID.size.z)
	for col in range(cols):
		for row in range(rows):
			var cell := Vector2i(col, row)
			var effects: Array = CombatServices.tile_effects_at(cell)
			if not effects.is_empty():
				_build_cell_marker(cell, effects)


## Rebuild ONLY [param cell]'s pips: free its old container (if any) and, if it
## still has effects, build a fresh row. Ensures no stale marker lingers on a cell
## whose effects were all removed (tile_effects_at now empty).
func _rebuild_cell(cell: Vector2i) -> void:
	var existing = _markers.get(cell, null)
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	_markers.erase(cell)

	if CombatServices == null:
		return
	var effects: Array = CombatServices.tile_effects_at(cell)
	if not effects.is_empty():
		_build_cell_marker(cell, effects)


# --- Marker construction -----------------------------------------------------

## Build the pip row for one cell and register it in [member _markers]. One pip
## per effect, colored via [TileEffectVisuals]; the row is centered over the cell
## and spread along X so multiple effects stay visually distinct (stacking read).
func _build_cell_marker(cell: Vector2i, effects: Array) -> void:
	var container := Node3D.new()
	container.name = "TileEffectMarker_%d_%d" % [cell.x, cell.y]

	# World-space center of the cell (cells are 2x2; center = cell*2+1), lifted to
	# PIP_Y so the row floats just over the tile top.
	var center: Vector3 = CombatServices.GRID.calculate_map_position(Vector3(cell.x, 0, cell.y))
	container.position = Vector3(center.x, PIP_Y, center.z)

	# Hazard materials pulse in _process; collect them on the container's meta so a
	# single-cell rebuild automatically drops the stale ones with the old node.
	var hazard_mats: Array = []

	# Center the row: pip i sits at (i - (n-1)/2) * PIP_SPACING along local X.
	var count: int = effects.size()
	var x0: float = -0.5 * float(count - 1) * PIP_SPACING
	for i in range(count):
		var effect = effects[i]
		if effect == null:
			continue
		var info: Dictionary = TileEffectVisuals.info_for(effect)
		var color: Color = info.get("color", Color.WHITE)
		var kind: String = String(info.get("kind", "neutral"))

		var pip := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(PIP_SIZE, PIP_SIZE)
		pip.mesh = mesh
		pip.position = Vector3(x0 + float(i) * PIP_SPACING, 0.0, 0.0)

		var mat := _make_pip_material(color, kind == "hazard")
		pip.material_override = mat
		if kind == "hazard":
			hazard_mats.append(mat)

		container.add_child(pip)

	container.set_meta("hazard_mats", hazard_mats)
	add_child(container)
	_markers[cell] = container


## Billboarded, unshaded pip material tinted [param color]. Mirrors HealthBar's
## billboard recipe (BILLBOARD_ENABLED + unshaded + keep_scale) so pips always
## face the camera at a constant on-screen size. Hazard pips get emission enabled
## so the _process pulse has something to modulate; buffs render flat/steady.
func _make_pip_material(color: Color, is_hazard: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.flags_unshaded = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	# Transparent so hazard pips can pulse their alpha; render above the tiles.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 3
	if is_hazard:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = PULSE_EMISSION.y
	return mat


# --- Signal handlers ---------------------------------------------------------

func _on_board_ready() -> void:
	# New board (map loaded / rebuilt): re-sweep every cell from scratch.
	_rebuild_all()


func _on_tile_effects_changed(cell: Vector2i) -> void:
	# One cell's runtime effects changed: restack just that cell.
	_rebuild_cell(cell)
