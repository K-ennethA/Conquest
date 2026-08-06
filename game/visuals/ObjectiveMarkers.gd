extends Node3D

class_name ObjectiveMarkers

## WORLD-SPACE OBJECTIVE BANNERS: one tall, low-poly pole-and-pennant standing over every
## base a map declares, tinted by the side that owns it, so the two things that actually
## decide a push/siege battle stay findable from full zoom-out.
##
## The first playtest of the 35x35 Riftwood reported that "visual clarity is harder on this
## big map": at a framing distance that fits a 1225-cell board, a base is a couple of pixels
## of unit silhouette among a thousand tiles. A 6-metre banner is three cells tall — it reads
## at any distance the camera can reach.
##
## GENERIC BY CONSTRUCTION. The ONLY input is [member MapResource.base_cells] (player slot ->
## cell) plus the owning slot's team colour. There is no mode check anywhere in this file:
## a map that authors bases gets banners whether it is played as Siege, as Destroy-the-Base,
## as a skirmish, in the Map Creator's preview or in a replay, and a map that authors none
## gets no node at all ([method build] returns null). Every dimension, colour weight and
## timing is an [code]@export[/code] on the node, so retuning the look is inspector work.
##
## LIFECYCLE mirrors [MapSurround] exactly: a sibling of "Tiles" under the map root, mounted
## by [MapLoader] after the board is built and freed with the map. Like the surround it adds
## ZERO board cells — nothing here is registered with [CombatServices], nothing carries a
## [Tile] script, nothing has a [CollisionObject3D], and it lives OUTSIDE "Map/Tiles" so
## [CameraController]'s fit rect cannot see it either. It also draws ZERO random numbers,
## from any stream: a decoration that consumed a match draw would desync every peer and
## every replay.
##
## CAPTURE URGENCY (optional, and optional in the strictest sense). While some mode
## controller reports a capture in flight, the banner standing on the contested cell pulses
## faster and burns brighter. That controller is found DUCK-TYPED — anything on the scene
## root exposing [code]capturing_by()[/code] — and every read is guarded, so with no mode
## controller installed the feature simply never fires and the banners bob at their calm
## idle rate. See [method urgent_cell].
##
## CONTROL POINTS (the second marker family, same rules end to end). A map may also declare
## [code]control_points[/code] — a plain [code]Array[/code] of [Vector2i] — and every cell in
## it gets a SMALLER marker: a short mast with a pennant and no finial, [member
## control_point_scale] of the base banner, so the two families are never confused for one
## another at a glance. A control point starts NEUTRAL STONE ([member neutral_stone]) and
## re-tints to the owning side's team colour the moment the mode says it changed hands; while
## a claim is in progress it runs the same urgent pulse a contested base does.
##
## Ownership is read on the SAME accumulator the capture urgency polls on — no second timer —
## through the same duck-typed controller: [code]control_point_owner(cell) -> int[/code]
## (-1 = neutral) and, if the controller happens to expose one, a claim-in-flight query —
## either [code]control_point_contested(cell) -> bool[/code] or the claimer-id form
## [SiegeController] answers, [code]control_point_claimer(cell) -> int[/code]. None of them is
## required: a build whose controller answers none leaves every control point neutral and calm,
## which is
## exactly what a map that authors control points but is played in a mode that does not score
## them should look like.
##
## CLAIM FEEDBACK. An ownership CHANGE also pushes one line through the battle's existing
## [ActionAnnouncer] — the surface the player already reads every move on — phrased from the
## LOCAL player's side when there is one ("Midpoint claimed!" / "Midpoint lost!") and
## neutrally when there is not. The first poll after a build only establishes the baseline, so
## a map that opens with a point already owned never announces it.
##
## A mode that announces claims ITSELF takes the line back: [SiegeController] does exactly
## that, on the beat the claim resolves, so on a Siege this layer re-tints and stays quiet.
## See [method _controller_announces] for how that is detected — the marker layer's own line
## exists for a mode with no voice of its own, and is never a second copy of the mode's.


# --- Layout ------------------------------------------------------------------

## Node name this builder always mounts under, and what tests / [MapLoader] look for.
const NODE_NAME := "ObjectiveMarkers"

## One board cell is 2x2 world units (see MapLoader._create_tile_at_position), and a cell's
## CENTER is at (x * 2 + 1, _, y * 2 + 1) — the same mapping units and the cursor use.
const CELL: float = 2.0
const HALF: float = 1.0

## Walkable surface height (matches LowPolyTileBuilder.CAP_TOP / MapSurround.CAP_TOP), so a
## banner is planted flush on the tile rather than floating above or sunk into it.
const GROUND_Y: float = 0.10

## "No cell" — what [method urgent_cell] returns when nothing is being captured. Never a
## valid board cell, so it can never accidentally match a marker.
const NO_CELL := Vector2i(-1, -1)


# --- Tunables (data; every one of these is inspector-editable) ---------------

## Height of the pole in world units. 6.4 is 3.2 board cells: at the 35x35 fit distance the
## banner is ~11% of screen height, which is the point of the whole feature.
@export var pole_height: float = 6.4
## Side of the square post. Chunky on purpose — a thin mast disappears at distance.
@export var pole_thickness: float = 0.34
## The plinth the pole is planted in, so it reads as built rather than stuck in the ground.
@export var plinth_size: float = 0.92
@export var plinth_height: float = 0.26

## Pennant wedge: a triangle hanging off one side of the mast, apex DOWN.
@export var banner_width: float = 1.55
@export var banner_height: float = 1.30
@export var banner_thickness: float = 0.18
## Cube finial capping the mast (rotated 45 degrees, so it reads as a faceted gem).
@export var finial_size: float = 0.42

## How far the banner rides up and down, and how long one full bob takes.
@export var bob_height: float = 0.45
@export var bob_seconds: float = 2.6

## Emission multiplier at the bottom and the top of the calm idle pulse.
@export var idle_emission: float = 0.22
@export var pulse_emission: float = 0.75
## How much of the team colour the mast keeps (0 = black, 1 = the banner's own tint).
@export var pole_shade: float = 0.55

## URGENCY: the bob duration is multiplied by this while a capture is in flight on the cell
## (smaller = faster), and the pulse peaks at [member urgent_emission] instead.
@export var urgent_speed: float = 0.32
@export var urgent_emission: float = 2.10

## Seconds between capture-state polls. The read is a duck-typed method call and a Dictionary
## lookup, so this is cheap; it exists so it is not done every single frame.
@export var urgency_poll_seconds: float = 0.20

## Optional explicit path to the mode controller [method urgent_cell] questions. Empty (the
## default) auto-discovers one on the scene root. A test injects its own stub through this.
## Assigning it DROPS the cached controller, so a late override always takes effect.
@export var mode_controller_path: NodePath = NodePath():
	set(value):
		mode_controller_path = value
		_controller = null


# --- Control points (tunables; same story — all data) ------------------------

## How much of a base banner a control-point marker is. 0.6 keeps it unmistakably the SAME
## family of object (chunky mast, hanging pennant) while reading as the lesser objective.
@export var control_point_scale: float = 0.6

## The colour an UNOWNED control point wears: a muted warm stone, desaturated out of the
## amber/brown theme family so it never reads as a faded team tint (which a blue-grey would).
@export var neutral_stone: Color = Color("8a8074")

## What an announcement calls the point when the map declares exactly ONE — the overwhelmingly
## common case, and the one where a bare "Control point" would be needlessly stiff.
@export var control_point_label: String = "Midpoint"
## Format used instead when the map declares several. Takes the 1-based point index.
@export var control_point_label_format: String = "Point %d"

## Set false to build the markers but never speak. The mode controller can also claim the
## announcement for itself — see [method _controller_announces].
@export var announce_ownership: bool = true

## Optional explicit path to the [ActionAnnouncer] claim lines are pushed through. Empty
## auto-discovers the battle HUD's own. Assigning it DROPS the cached one.
@export var announcer_path: NodePath = NodePath():
	set(value):
		announcer_path = value
		_announcer = null


# --- Instance state ----------------------------------------------------------

## The layout this instance was built from — see [method plan]. Read by tests and by anything
## that wants the marker set without walking the node tree.
var layout: Array[Dictionary] = []

## player slot -> the marker root Node3D standing over that player's base.
var _markers: Dictionary = {}
## player slot -> live per-marker presentation state:
## { cell, banner (Node3D), base_y, mats (Array[StandardMaterial3D]), urgent (bool),
##   bob_seconds (float), emission_peak (float), tween (Tween) }
var _state: Dictionary = {}

## The control-point layout this instance was built from — see [method plan_control_points].
var control_point_layout: Array[Dictionary] = []

## point index -> the marker root Node3D standing on that control point.
var _cp_markers: Dictionary = {}
## point index -> live per-marker presentation state. Same shape as [member _state] plus
## { index, owner (int, -1 neutral), seen (bool: has a poll established the baseline yet) }.
var _cp_state: Dictionary = {}

## Cached mode controller (see [method _mode_controller]) and the poll accumulator.
var _controller: Object = null
var _poll_accum: float = 0.0

## Cached [ActionAnnouncer] (see [method _announcer_node]).
var _announcer: Object = null


# =============================================================================
# PLANNING (pure, static, no scene tree, no RNG of any kind)
# =============================================================================

## The team colour for [param player_id]: the LIVE player's own team colour when a
## [PlayerManager] is up (so a custom-coloured side gets a matching banner), else the same
## [PlayerMaterials] constants the unit team tints fall back to. Never fails — an unknown
## slot is neutral grey.
static func color_for_player(player_id: int) -> Color:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		var pm = (loop as SceneTree).root.get_node_or_null("PlayerManager")
		if pm != null and pm.has_method("get_player_by_id"):
			var player = pm.get_player_by_id(player_id)
			if player != null and is_instance_valid(player) and player.has_method("get_team_color"):
				return player.get_team_color()
	match player_id:
		0:
			return PlayerMaterials.PLAYER_1_PRIMARY
		1:
			return PlayerMaterials.PLAYER_2_PRIMARY
	return PlayerMaterials.NEUTRAL_PRIMARY


## World position of the CENTER of board cell [param cell], on the tile surface.
static func world_position_for(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * CELL + HALF, GROUND_Y, float(cell.y) * CELL + HALF)


## Every banner [param map] asks for, in ASCENDING PLAYER SLOT order (deterministic, so two
## peers build the same node names in the same order).
##
## Each entry: { player_id: int, cell: Vector2i, color: Color, world: Vector3 }.
##
## Reads [member MapResource.base_cells] and NOTHING else — that dictionary is the whole
## contract, which is what makes this work on any map that authors bases and cost nothing on
## any map that does not. A junk or out-of-bounds entry is skipped rather than rejected: a
## bad decoration must never cost a battle (MapResource.validate_map already flags them).
static func plan(map) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null:
		return out
	var bases = map.get("base_cells")
	if not (bases is Dictionary):
		return out

	var width: int = int(map.get("width")) if map.get("width") != null else 0
	var height: int = int(map.get("height")) if map.get("height") != null else 0

	var keys: Array = (bases as Dictionary).keys()
	keys.sort()
	for key in keys:
		var value = (bases as Dictionary)[key]
		if not (value is Vector2i):
			continue
		var cell: Vector2i = value
		if cell.x < 0 or cell.y < 0:
			continue
		if width > 0 and cell.x >= width:
			continue
		if height > 0 and cell.y >= height:
			continue
		var player_id: int = int(key)
		out.append({
			"player_id": player_id,
			"cell": cell,
			"color": color_for_player(player_id),
			"world": world_position_for(cell),
		})
	return out


## Every CONTROL POINT [param map] declares, in AUTHORED ORDER (which is deterministic — it is
## the order the array was written in, identical on every peer and in every replay).
##
## Each entry: { index: int, cell: Vector2i, world: Vector3 }. No colour: a control point is
## born neutral and only ever learns an owner from the live mode (see
## [method refresh_control_points]).
##
## Reads [code]map.control_points[/code] and NOTHING else — the same one-property contract
## [method plan] has with [member MapResource.base_cells], and the reason this works on a map
## resource that does not carry the property at all (the read is a guarded [code]get()[/code],
## so an older map simply plans nothing). Junk, out-of-bounds and DUPLICATE cells are skipped
## rather than rejected: a broken decoration must never cost a battle, and two markers stacked
## on one cell would z-fight forever.
static func plan_control_points(map) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if map == null:
		return out
	# The map's own ACCESSOR when it has one: it coerces a JSON round-trip's decoded entries
	# back into cells (CONQUEST.md rule 3), which reading the raw array cannot do. The raw
	# property is the fallback, so a map-shaped object that is only the property still plans.
	var raw
	if map.has_method("get_control_points"):
		raw = map.call("get_control_points")
	else:
		raw = map.get("control_points")
	if not (raw is Array):
		return out

	var width: int = int(map.get("width")) if map.get("width") != null else 0
	var height: int = int(map.get("height")) if map.get("height") != null else 0

	var seen: Dictionary = {}
	for value in (raw as Array):
		if not (value is Vector2i):
			continue
		var cell: Vector2i = value
		if cell.x < 0 or cell.y < 0:
			continue
		if width > 0 and cell.x >= width:
			continue
		if height > 0 and cell.y >= height:
			continue
		if seen.has(cell):
			continue
		seen[cell] = true
		out.append({
			"index": out.size(),
			"cell": cell,
			"world": world_position_for(cell),
		})
	return out


## The colour a control point owned by [param owner_id] wears: the owning side's team tint, or
## [param stone] while it is neutral (owner < 0). The ONE place that decision is made, so the
## build and every later re-tint can never disagree about what "unowned" looks like.
static func control_point_color(owner_id: int, stone: Color) -> Color:
	if owner_id < 0:
		return stone
	return color_for_player(owner_id)


# =============================================================================
# BUILDING
# =============================================================================

## Build (or REBUILD) the markers for [param map] under [param map_root], returning the
## mounted node — or null when the map declares neither a usable base NOR a usable control
## point, in which case NOTHING is mounted at all. Any stray node already named
## [constant NODE_NAME] is freed first, so a second load can never leave two sets stacked on
## one board.
static func build(map, map_root: Node3D) -> ObjectiveMarkers:
	if map_root == null:
		return null
	var stale := map_root.get_node_or_null(NODE_NAME)
	if stale != null:
		map_root.remove_child(stale)
		stale.free()
	if map == null or (plan(map).is_empty() and plan_control_points(map).is_empty()):
		return null

	var node := ObjectiveMarkers.new()
	node.name = NODE_NAME
	map_root.add_child(node)
	node.generate(map)
	return node


## Populate this node with one banner per declared base and one small marker per declared
## control point. Idempotent: existing markers are cleared (and their tweens killed) first.
func generate(map) -> void:
	_clear()
	layout = plan(map)
	control_point_layout = plan_control_points(map)
	if layout.is_empty() and control_point_layout.is_empty():
		set_process(false)
		return

	# ONE material built here and DUPLICATED per marker before tinting (CONQUEST.md
	# convention 7): the banners must never share a mutated material with each other, let
	# alone with anything on the board.
	var base_mat := _base_material()

	for entry in layout:
		var player_id: int = int(entry["player_id"])
		var marker := _build_marker(entry, base_mat)
		add_child(marker)
		_markers[player_id] = marker

	# Control points second, so the node order is bases-then-points on every peer.
	for entry in control_point_layout:
		var index: int = int(entry["index"])
		var marker := _build_control_point_marker(entry, base_mat)
		add_child(marker)
		_cp_markers[index] = marker

	_apply_all_animations()
	set_process(true)


## The prototype every banner material is duplicated from. Flat, unlit-ish and emissive, so
## the tint survives whatever the map's lighting preset does to the board.
static func _base_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 0.0
	return mat


## One banner: plinth + mast, plus a "Banner" child (pennant + finial) that is the part the
## bob/pulse animates. Every piece is a BoxMesh or a PrismMesh — flat-shaded by construction,
## which is the chunky low-poly vibe the tiles are built in.
func _build_marker(entry: Dictionary, base_mat: StandardMaterial3D) -> Node3D:
	var player_id: int = int(entry["player_id"])
	var cell: Vector2i = entry["cell"]
	var color: Color = entry["color"]

	var root := Node3D.new()
	root.name = "Marker%d" % player_id
	root.position = entry["world"]
	root.set_meta("player_id", player_id)
	root.set_meta("cell", cell)

	# Mast + plinth take a DARKENED duplicate, so the pennant stays the brightest thing on
	# the banner and the silhouette still reads as one object.
	var pole_mat: StandardMaterial3D = base_mat.duplicate() as StandardMaterial3D
	pole_mat.albedo_color = _shaded(color, pole_shade)
	pole_mat.emission = color
	pole_mat.emission_energy_multiplier = idle_emission * 0.4

	var banner_mat: StandardMaterial3D = base_mat.duplicate() as StandardMaterial3D
	banner_mat.albedo_color = color
	banner_mat.emission = color
	banner_mat.emission_energy_multiplier = idle_emission

	var plinth := _box(Vector3(plinth_size, plinth_height, plinth_size), pole_mat)
	plinth.name = "Plinth"
	plinth.position = Vector3(0.0, plinth_height * 0.5, 0.0)
	root.add_child(plinth)

	var pole := _box(Vector3(pole_thickness, pole_height, pole_thickness), pole_mat)
	pole.name = "Pole"
	pole.position = Vector3(0.0, pole_height * 0.5, 0.0)
	root.add_child(pole)

	# The animated group, parked at the top of the mast.
	var banner := Node3D.new()
	banner.name = "Banner"
	banner.position = Vector3(0.0, pole_height, 0.0)
	root.add_child(banner)

	var finial := _box(Vector3(finial_size, finial_size, finial_size), banner_mat)
	finial.name = "Finial"
	finial.position = Vector3(0.0, finial_size * 0.5, 0.0)
	finial.rotation = Vector3(0.0, PI * 0.25, 0.0)
	banner.add_child(finial)

	# The pennant: a triangular prism turned apex-DOWN and hung off one side of the mast, so
	# the banner has an asymmetric silhouette that reads as a flag from the authored camera
	# angle instead of a symmetrical blob.
	var prism := PrismMesh.new()
	prism.size = Vector3(banner_width, banner_height, banner_thickness)
	var pennant := MeshInstance3D.new()
	pennant.name = "Pennant"
	pennant.mesh = prism
	pennant.material_override = banner_mat
	pennant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pennant.rotation = Vector3(0.0, 0.0, PI)
	pennant.position = Vector3(
		pole_thickness * 0.5 + banner_width * 0.5,
		-banner_height * 0.5 - finial_size * 0.25,
		0.0)
	banner.add_child(pennant)

	_state[player_id] = {
		"cell": cell,
		"banner": banner,
		"base_y": pole_height,
		"mats": [banner_mat, pole_mat],
		"urgent": false,
		"bob_seconds": bob_seconds,
		"emission_peak": pulse_emission,
		"tween": null,
	}
	return root


## One flat-shaded box of [param size], sharing [param mat]. Shadows off throughout: a
## 6-metre mast casting a shadow across the board would read as terrain.
func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## [param base] pulled [param keep] of the way from black toward itself. Alpha preserved.
static func _shaded(base: Color, keep: float) -> Color:
	var k: float = clampf(keep, 0.0, 1.0)
	return Color(base.r * k, base.g * k, base.b * k, base.a)


## [member control_point_scale], floored so a mis-authored 0 (or a negative) cannot collapse a
## marker into a zero-size mesh the player can never see.
func _cp_scale() -> float:
	return maxf(control_point_scale, 0.05)


## Height of a control point's mast — and, since it wears no finial, its full height. Strictly
## shorter than [method top_height]: that difference IS how the player tells the lesser
## objective from a base at a glance.
func control_point_top_height() -> float:
	return pole_height * _cp_scale()


## One control-point marker: a short mast with a pennant hanging off it, and nothing else — no
## plinth, no finial. Deliberately a SUBSET of the base banner's silhouette rather than a
## different shape: same family, obviously lesser.
##
## Built NEUTRAL. The owner is learned from the mode on the first poll
## ([method refresh_control_points]), which is also what makes a control point look right on a
## map that authors them in a mode that does not score them.
func _build_control_point_marker(entry: Dictionary, base_mat: StandardMaterial3D) -> Node3D:
	var index: int = int(entry["index"])
	var cell: Vector2i = entry["cell"]
	var scale_factor: float = _cp_scale()
	var mast_height: float = pole_height * scale_factor
	var mast_thickness: float = pole_thickness * scale_factor
	var flag_width: float = banner_width * scale_factor
	var flag_height: float = banner_height * scale_factor
	var flag_thickness: float = banner_thickness * scale_factor

	var root := Node3D.new()
	root.name = "ControlPoint%d" % index
	root.position = entry["world"]
	root.set_meta("control_point_index", index)
	root.set_meta("cell", cell)

	# DUPLICATED per marker before a single tint touches them (CONQUEST.md convention 7) —
	# doubly load-bearing here, because these two materials are re-tinted in place every time
	# the point changes hands, and a shared one would recolour the whole board.
	var color: Color = control_point_color(-1, neutral_stone)
	var pole_mat: StandardMaterial3D = base_mat.duplicate() as StandardMaterial3D
	var banner_mat: StandardMaterial3D = base_mat.duplicate() as StandardMaterial3D

	var pole := _box(Vector3(mast_thickness, mast_height, mast_thickness), pole_mat)
	pole.name = "Pole"
	pole.position = Vector3(0.0, mast_height * 0.5, 0.0)
	root.add_child(pole)

	var banner := Node3D.new()
	banner.name = "Banner"
	banner.position = Vector3(0.0, mast_height, 0.0)
	root.add_child(banner)

	var prism := PrismMesh.new()
	prism.size = Vector3(flag_width, flag_height, flag_thickness)
	var pennant := MeshInstance3D.new()
	pennant.name = "Pennant"
	pennant.mesh = prism
	pennant.material_override = banner_mat
	pennant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pennant.rotation = Vector3(0.0, 0.0, PI)
	pennant.position = Vector3(
		mast_thickness * 0.5 + flag_width * 0.5,
		-flag_height * 0.5,
		0.0)
	banner.add_child(pennant)

	_cp_state[index] = {
		"index": index,
		"cell": cell,
		"banner": banner,
		"base_y": mast_height,
		"mats": [banner_mat, pole_mat],
		"owner": -1,
		"seen": false,
		"urgent": false,
		"bob_seconds": bob_seconds,
		"emission_peak": pulse_emission,
		"tween": null,
	}
	_tint_control_point(_cp_state[index], color)
	return root


## Repaint one control point's own (already duplicated) materials to [param color]. The mast
## keeps the same darkened fraction of it the base banners' masts do, so an owned point reads
## as one object in the owner's colour rather than two.
func _tint_control_point(state: Dictionary, color: Color) -> void:
	var mats: Array = state["mats"]
	var banner_mat: StandardMaterial3D = mats[0]
	var pole_mat: StandardMaterial3D = mats[1]
	banner_mat.albedo_color = color
	banner_mat.emission = color
	pole_mat.albedo_color = _shaded(color, pole_shade)
	pole_mat.emission = color
	pole_mat.emission_energy_multiplier = idle_emission * 0.4


# =============================================================================
# ANIMATION (bob + pulse, and the capture-urgency escalation)
# =============================================================================

## Total height of a banner from the tile surface to the top of its finial — the number that
## decides whether it is legible at full zoom-out.
func top_height() -> float:
	return pole_height + finial_size


## The marker root over [param player_id]'s base, or null.
func marker_for(player_id: int) -> Node3D:
	var node = _markers.get(player_id)
	return node if node != null and is_instance_valid(node) else null


## player slot -> the cell its banner stands on.
func marker_cells() -> Dictionary:
	var out: Dictionary = {}
	for player_id in _state:
		out[player_id] = (_state[player_id] as Dictionary)["cell"]
	return out


## True while [param player_id]'s banner is running the URGENT (fast, bright) pulse.
func is_urgent(player_id: int) -> bool:
	if not _state.has(player_id):
		return false
	return bool((_state[player_id] as Dictionary)["urgent"])


## The bob duration [param player_id]'s banner is currently running at (seconds). Smaller
## under urgency — this is what "pulses faster" means, exposed so it can be pinned.
func bob_seconds_for(player_id: int) -> float:
	if not _state.has(player_id):
		return 0.0
	return float((_state[player_id] as Dictionary)["bob_seconds"])


## The emission multiplier [param player_id]'s pulse peaks at. Larger under urgency — this is
## what "brighter" means.
func emission_peak_for(player_id: int) -> float:
	if not _state.has(player_id):
		return 0.0
	return float((_state[player_id] as Dictionary)["emission_peak"])


## ONE accumulator drives BOTH polls — the base banners' capture urgency and the control
## points' ownership. A second timer for the second feature would be a second thing to keep in
## step with the first for no gain: the reads are duck-typed method calls, and they want the
## same cadence anyway.
func _process(delta: float) -> void:
	if _state.is_empty() and _cp_state.is_empty():
		return
	_poll_accum += delta
	if _poll_accum < maxf(urgency_poll_seconds, 0.0):
		return
	_poll_accum = 0.0
	refresh_urgency()
	refresh_control_points()


## Re-read the capture state and re-animate ONLY the banners whose urgency actually flipped,
## so a battle with no capture in flight never rebuilds a tween.
func refresh_urgency() -> void:
	var hot: Vector2i = urgent_cell()
	for player_id in _state:
		var state: Dictionary = _state[player_id]
		var want: bool = hot != NO_CELL and (state["cell"] as Vector2i) == hot
		if want == bool(state["urgent"]):
			continue
		state["urgent"] = want
		_apply_animation(int(player_id))


## The cell a capture is currently being contested on, or [constant NO_CELL].
##
## Entirely duck-typed and entirely optional. It asks whatever object [method
## _mode_controller] found — if there is none, or it lacks the methods, or nothing is being
## captured, the answer is NO_CELL and every banner stays calm. Prefers the controller's own
## reported capture cell (the precise answer) and falls back to "the base the capturing side
## is attacking", so a controller exposing only [code]capturing_by()[/code] still works.
func urgent_cell() -> Vector2i:
	var ctrl := _mode_controller()
	if ctrl == null:
		return NO_CELL
	if not ctrl.has_method("capturing_by"):
		return NO_CELL
	var side: int = int(ctrl.call("capturing_by"))
	if side < 0:
		return NO_CELL
	if ctrl.has_method("capture_state"):
		var state = ctrl.call("capture_state")
		if state is Dictionary and (state as Dictionary).has("cell"):
			var cell = (state as Dictionary)["cell"]
			if cell is Vector2i:
				return cell
	if ctrl.has_method("enemy_base_cell_for"):
		var enemy = ctrl.call("enemy_base_cell_for", side)
		if enemy is Vector2i:
			return enemy
	return NO_CELL


## The mode controller to question, or null. An explicit [member mode_controller_path] wins;
## otherwise the scene root's DIRECT children are scanned for anything exposing EITHER of the
## two things this layer ever asks a mode: [code]capturing_by()[/code] (base urgency) or
## [code]control_point_owner()[/code] (who holds a point). Never a preload, never a class
## reference — this file must compile and run in a project with no mode controllers at all.
func _mode_controller() -> Object:
	if _controller != null and not is_instance_valid(_controller):
		_controller = null
	if _controller != null:
		return _controller

	if mode_controller_path != NodePath() and has_node(mode_controller_path):
		_controller = get_node(mode_controller_path)
		return _controller

	# get_tree() on a detached node is an ENGINE ERROR in Godot 4, not a null -- and GUT
	# fails a test on any engine error. A banner set that is not in the tree simply has no
	# mode to ask.
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	for child in tree.root.get_children():
		if child.has_method("capturing_by") or child.has_method("control_point_owner"):
			_controller = child
			return _controller
	return null


func _apply_all_animations() -> void:
	for player_id in _state:
		_apply_animation(int(player_id))
	for index in _cp_state:
		_apply_control_point_animation(int(index))


## (Re)start one BASE banner's bob + pulse at its current urgency.
func _apply_animation(player_id: int) -> void:
	if not _state.has(player_id):
		return
	_animate_state(_state[player_id])


## (Re)start one CONTROL POINT marker's bob + pulse. Shares [method _animate_state] with the
## base banners rather than re-deriving the timing, so "urgent" means exactly the same thing
## on both marker families.
func _apply_control_point_animation(index: int) -> void:
	if not _cp_state.has(index):
		return
	_animate_state(_cp_state[index])


## (Re)start one marker's bob + pulse at its current urgency. Killed and replaced rather than
## stacked. With animations OFF the marker is parked at its resting pose and lit at the idle
## level — still perfectly legible, just not moving (the same contract the rest of the FX
## layer honours for a zero authored duration).
func _animate_state(state: Dictionary) -> void:
	var live = state["tween"]
	if live != null and (live as Tween).is_valid():
		(live as Tween).kill()
	state["tween"] = null

	var urgent: bool = bool(state["urgent"])
	var duration: float = maxf(bob_seconds, 0.05)
	if urgent:
		duration = maxf(duration * maxf(urgent_speed, 0.01), 0.05)
	var peak: float = urgent_emission if urgent else pulse_emission
	state["bob_seconds"] = duration
	state["emission_peak"] = peak

	var banner: Node3D = state["banner"]
	var base_y: float = float(state["base_y"])
	var mats: Array = state["mats"]
	var banner_mat: StandardMaterial3D = mats[0]

	if banner == null or not is_instance_valid(banner):
		return
	banner.position.y = base_y
	banner_mat.emission_energy_multiplier = idle_emission

	if not _animations_on() or not is_inside_tree():
		return

	var half: float = duration * 0.5
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(banner, "position:y", base_y + bob_height, half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(banner_mat, "emission_energy_multiplier", peak, half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(banner, "position:y", base_y, half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(banner_mat, "emission_energy_multiplier", idle_emission, half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	state["tween"] = tween


## The presentation toggle, read null-safely: with no GameSettings autoload (headless runs,
## bare test harnesses) banners animate exactly as they do in a normal battle.
func _animations_on() -> bool:
	if not is_inside_tree():
		return true
	var tree := get_tree()
	if tree == null or tree.root == null:
		return true
	var gs = tree.root.get_node_or_null("GameSettings")
	if gs == null or not gs.has_method("animations_on"):
		return true
	return bool(gs.animations_on())


# =============================================================================
# CONTROL POINTS: ownership, re-tint, and the claim line
# =============================================================================

## The marker root standing on control point [param index], or null.
func control_point_marker(index: int) -> Node3D:
	var node = _cp_markers.get(index)
	return node if node != null and is_instance_valid(node) else null


## Every control point's cell, in the same order [method plan_control_points] produced them.
func control_point_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for entry in control_point_layout:
		out.append(entry["cell"])
	return out


## How many control points this instance is showing.
func control_point_count() -> int:
	return control_point_layout.size()


## The owner control point [param index] is currently PAINTED as: a player slot, or -1 while
## it is neutral. This is the presentation's own belief, which is the thing worth asserting —
## the mode's answer is only interesting once it has been rendered.
func control_point_owner_shown(index: int) -> int:
	if not _cp_state.has(index):
		return -1
	return int((_cp_state[index] as Dictionary)["owner"])


## The colour control point [param index]'s pennant is actually wearing.
func control_point_tint(index: int) -> Color:
	if not _cp_state.has(index):
		return neutral_stone
	var mats: Array = (_cp_state[index] as Dictionary)["mats"]
	return (mats[0] as StandardMaterial3D).albedo_color


## True while control point [param index] is running the urgent (fast, bright) pulse because
## a claim is in progress on it.
func is_control_point_urgent(index: int) -> bool:
	if not _cp_state.has(index):
		return false
	return bool((_cp_state[index] as Dictionary)["urgent"])


## Re-read every control point's owner and contest state, and change ONLY what actually moved.
##
## Called from the shared poll (see [method _process]) and directly by tests. Everything it
## asks the mode is optional: a controller that cannot answer [code]control_point_owner[/code]
## leaves every point neutral, and one that cannot answer
## [code]control_point_contested[/code] leaves every point calm.
func refresh_control_points() -> void:
	if _cp_state.is_empty():
		return
	var ctrl := _mode_controller()
	var can_own: bool = ctrl != null and ctrl.has_method("control_point_owner")
	# Two spellings of "is somebody taking this?", both honoured: a plain boolean, and the
	# claimer-id form [SiegeController] answers (the midpoint mirror of capturing_by).
	var can_contest: bool = ctrl != null and ctrl.has_method("control_point_contested")
	var can_claimer: bool = ctrl != null and ctrl.has_method("control_point_claimer")

	for index in _cp_state:
		var state: Dictionary = _cp_state[index]
		var cell: Vector2i = state["cell"]

		var owner_id: int = -1
		if can_own:
			var raw = ctrl.call("control_point_owner", cell)
			if raw != null:
				owner_id = int(raw)
		if owner_id < 0:
			owner_id = -1

		var previous: int = int(state["owner"])
		var first_look: bool = not bool(state["seen"])
		state["seen"] = true
		if owner_id != previous:
			state["owner"] = owner_id
			_tint_control_point(state, control_point_color(owner_id, neutral_stone))
			# The FIRST poll only establishes the baseline. A map that opens with a point
			# already held has not just changed hands, and announcing it would greet the
			# player with a claim they never made.
			if not first_look:
				_announce_claim(int(index), previous, owner_id)

		var want_urgent: bool = false
		if can_contest:
			want_urgent = bool(ctrl.call("control_point_contested", cell))
		elif can_claimer:
			want_urgent = int(ctrl.call("control_point_claimer", cell)) >= 0
		if want_urgent != bool(state["urgent"]):
			state["urgent"] = want_urgent
			_apply_control_point_animation(int(index))


## What an announcement calls control point [param index]: the authored single-point name when
## the map declares exactly one, and a numbered one otherwise. Never an index the player has
## to translate — the format is 1-based.
func control_point_name(index: int) -> String:
	if control_point_layout.size() <= 1:
		return control_point_label
	return control_point_label_format % (index + 1)


## The local player's slot, or -1 when this build has no local side to speak for (a replay, a
## spectator, a bare test harness). -1 is what switches the claim line to neutral wording, so
## it is answered honestly rather than defaulted to player 0.
func _local_slot() -> int:
	if typeof(GameModeManager) != TYPE_OBJECT or GameModeManager == null:
		return -1
	if not GameModeManager.has_method("get_local_player_id"):
		return -1
	var raw = GameModeManager.get_local_player_id()
	if raw == null:
		return -1
	return int(raw)


## The line one ownership change earns, as { text, sub, color }. PURE — no tree, no announcer,
## no state — so the wording can be pinned without mounting a HUD.
##
## [param local_slot] < 0 means "no local side": the line then states what happened without
## taking a side, which is the right voice for a replay or a spectator.
static func claim_line(point_name: String, previous_owner: int, owner_id: int, local_slot: int) -> Dictionary:
	if local_slot >= 0:
		if owner_id == local_slot:
			return {
				"text": "%s claimed!" % point_name,
				"sub": "",
				"color": ActionAnnouncer.ALLY_COLOR,
			}
		if owner_id >= 0:
			# Theirs now — whether it was ours a moment ago or nobody's, the thing the player
			# needs to read is the same: that point is working against them.
			return {
				"text": "%s lost!" % point_name,
				"sub": "",
				"color": ActionAnnouncer.ENEMY_COLOR,
			}
		return {
			"text": "%s neutral" % point_name,
			"sub": "",
			"color": ActionAnnouncer.NEUTRAL_COLOR,
		}
	if owner_id >= 0:
		return {
			"text": "%s claimed" % point_name,
			"sub": "Player %d" % (owner_id + 1),
			"color": ActionAnnouncer.NEUTRAL_COLOR,
		}
	var sub: String = "" if previous_owner < 0 else "Player %d lost it" % (previous_owner + 1)
	return {
		"text": "%s neutral" % point_name,
		"sub": sub,
		"color": ActionAnnouncer.NEUTRAL_COLOR,
	}


## Push one claim line through the battle's existing [ActionAnnouncer]. Silent when the
## feature is switched off, when the mode controller says it announces claims itself, or when
## there is no announcer to speak through — none of which is an error.
func _announce_claim(index: int, previous_owner: int, owner_id: int) -> void:
	if not announce_ownership:
		return
	if _controller_announces():
		return
	var announcer := _announcer_node()
	if announcer == null or not announcer.has_method("announce"):
		return
	var line: Dictionary = claim_line(
		control_point_name(index), previous_owner, owner_id, _local_slot())
	announcer.call("announce", String(line["text"]), String(line["sub"]), line["color"])


## True when the MODE already announces its own claims, so this layer must not double them.
##
## THIS IS THE DIVISION OF LABOUR. [SiegeController] announces a midpoint changing hands
## itself — it is the side that knows who took it and when, and it does so on the beat the
## claim resolves rather than on a presentation poll. So on a Siege the marker layer re-tints
## and stays quiet, and the line the player hears is the mode's one, once.
##
## Probed rather than hard-coded, in two forms: an explicit
## [code]announces_control_points()[/code] opt-in, and the mere PRESENCE of a controller-side
## announce entry point. Anything answering neither is assumed to say nothing, which is what
## keeps this layer's own line available to a mode that has no voice of its own.
func _controller_announces() -> bool:
	var ctrl := _mode_controller()
	if ctrl == null:
		return false
	if ctrl.has_method("announces_control_points"):
		return bool(ctrl.call("announces_control_points"))
	return ctrl.has_method("_announce_control_point")


## The [ActionAnnouncer] to speak through, or null. An explicit [member announcer_path] wins
## (that is how a test injects a recorder); otherwise the CURRENT SCENE is searched once for
## the HUD's own, and the answer — including "there isn't one" — is cached.
func _announcer_node() -> Object:
	if _announcer != null and not is_instance_valid(_announcer):
		_announcer = null
	if _announcer != null:
		return _announcer

	if announcer_path != NodePath() and has_node(announcer_path):
		_announcer = get_node(announcer_path)
		return _announcer

	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	var found := tree.current_scene.find_child("ActionAnnouncer", true, false)
	if found != null and found.has_method("announce"):
		_announcer = found
	return _announcer


# =============================================================================
# TEARDOWN
# =============================================================================

func _clear() -> void:
	_kill_tweens(_state)
	_kill_tweens(_cp_state)
	_state.clear()
	_cp_state.clear()
	_markers.clear()
	_cp_markers.clear()
	layout = []
	control_point_layout = []
	for child in get_children():
		remove_child(child)
		child.free()


func _exit_tree() -> void:
	# Drop every in-flight bob. The tweens die with the node, but killing them explicitly
	# means a re-added instance can never believe a stale one is still running.
	_kill_tweens(_state)
	_kill_tweens(_cp_state)
	_controller = null
	_announcer = null


## Kill (and forget) every live tween held in a marker state table.
func _kill_tweens(table: Dictionary) -> void:
	for key in table:
		var state: Dictionary = table[key]
		var live = state["tween"]
		if live != null and (live as Tween).is_valid():
			(live as Tween).kill()
		state["tween"] = null
