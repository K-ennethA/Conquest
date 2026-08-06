extends GutTest

## CONTROL POINT MARKERS on a REAL mounted board.
##
## The base banners ([ObjectiveMarkers]) made the two things that END a siege findable from
## full zoom-out. Control points are the things that DECIDE one while it is still being
## played, and they had no world-space presence at all: a cell that changes hands and looks
## exactly like the 1224 cells around it.
##
## What is proven here, all of it against the board [MapLoader] really builds:
##
##   1. a SMALLER marker on every cell the map's [code]control_points[/code] declares --
##      strictly shorter than a base banner, so the lesser objective reads as the lesser one;
##   2. NEUTRAL STONE until somebody owns it, then the owner's team tint, on materials that
##      are that marker's OWN (re-tinting one can never recolour another, or the board);
##   3. ownership polled off the SAME accumulator the capture urgency already runs on, through
##      the same duck-typed controller -- and degrading to "neutral and calm" when the mode
##      cannot answer, which is every mode that does not score control points;
##   4. one CLAIM LINE through the battle's existing [ActionAnnouncer] per change of hands,
##      phrased from the local player's side, silent on the baseline poll and silent when the
##      mode controller announces claims itself;
##   5. and that all of it is DECORATION: no board cells, no colliders, no tile effects, freed
##      with the map.
##
## THE FIXTURE. Riftwood is used when it declares control points; until that lands, the suite
## builds its own map that declares them, through the real [MapLoader] into a real board. The
## map resource is a runtime subclass of [MapResource] carrying the pinned
## [code]control_points[/code] property ONLY while the shipped resource does not carry it yet
## -- see [method _new_map] -- so this suite keeps passing unchanged the day it lands.

const MARKERS := preload("res://game/visuals/ObjectiveMarkers.gd")
const RIFTWOOD_PATH := "res://game/maps/resources/riftwood.tres"
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Where [method _new_map] generates its stand-in map script while the shipped [MapResource]
## does not declare control points yet. A TEMP path, deleted in after_all (tests/README rule 4).
const TEMP_SCRIPT_PATH := "user://test_control_point_map.gd"

## Untyped on purpose -- see tests/README.md rule 3.
var _guard

## The shared board Grid MapLoader resizes to the loaded map: process-wide state, so its size
## is snapshot and restored.
var _grid: Grid = null
var _grid_size_before: Vector3 = Vector3.ZERO

var _scene_before: Node = null
## Root-mounted by hand (current_scene must be a direct child of root), so it cannot use
## add_child_autofree.
var _scene: Node3D = null
var _map_node: Node3D = null
var _loader: MapLoader = null
var _map_res: MapResource = null

## Nodes a single test injected under the markers. Removed by after_each even when the test
## that added them failed part-way.
var _injected: Array[Node] = []

## What the LIFECYCLE half of this suite observed, recorded in [method before_all].
##
## Loading a board is done there, once, rather than inside the tests that assert on it, for a
## reason that is about this project rather than about style: [code]MapLoader[/code] re-parses
## a tile scene per cell, and two of the shipped tile scenes carry invalid ext_resource UIDs,
## so EVERY map load prints a wall of engine warnings — and GUT fails a test on any engine
## error (tests/README rule 1). The mutations therefore happen up front and the tests assert
## on the facts production produced. See [method _observe_lifecycle].
var _lifecycle: Dictionary = {}


# =============================================================================
# Fixture
# =============================================================================

func before_all() -> void:
	_grid = load("res://board/Grid.tres") as Grid
	if _grid != null:
		_grid_size_before = _grid.size
	_scene_before = get_tree().current_scene
	if CombatServices:
		CombatServices.clear()

	_map_res = _fixture_map()

	_scene = Node3D.new()
	_scene.name = "TestControlPointBoard"
	get_tree().root.add_child(_scene)

	_map_node = Node3D.new()
	_map_node.name = "Map"
	_scene.add_child(_map_node)

	_loader = MapLoader.new()
	_map_node.add_child(_loader)
	if _map_res != null:
		_loader.load_map(_map_res, _map_node)

	_lifecycle = _observe_lifecycle()

	# AFTER the load, exactly as test_objective_markers_live.gd does: Unit's visual manager
	# conjures the whole battle visual stack under whatever current_scene is when a unit
	# enters the tree, and this suite is about board decoration.
	get_tree().current_scene = _scene

	if CombatServices:
		CombatServices.rebuild(_map_node)


func before_each() -> void:
	_guard = Guard.new()
	# Every test starts from a freshly generated marker set, so ownership one test stubbed in
	# can never be the state the next one starts from.
	var markers := _markers_node()
	if markers != null and _map_res != null:
		markers.generate(_map_res)


func after_each() -> void:
	var markers := _markers_node()
	if markers != null:
		markers.mode_controller_path = NodePath()
		markers.announcer_path = NodePath()
	for node in _injected:
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_injected.clear()

	if _scene != null and is_instance_valid(_scene) and get_tree().current_scene != _scene:
		get_tree().current_scene = _scene
	_guard.restore()


func after_all() -> void:
	if get_tree().current_scene != _scene_before:
		get_tree().current_scene = _scene_before
	if _scene != null and is_instance_valid(_scene):
		get_tree().root.remove_child(_scene)
		_scene.free()
	_scene = null
	_map_node = null
	_loader = null
	if CombatServices:
		CombatServices.clear()
	if _grid != null:
		_grid.size = _grid_size_before
	_map_res = null
	if FileAccess.file_exists(TEMP_SCRIPT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SCRIPT_PATH))


# --- Fixture helpers ---------------------------------------------------------

## The map this suite runs on: the shipped Riftwood as soon as it declares control points, and
## a purpose-built one until then. Either way the markers are earned by the DATA alone.
func _fixture_map() -> MapResource:
	var rift := load(RIFTWOOD_PATH) as MapResource
	if rift != null and not _raw_points(rift).is_empty():
		return rift
	return _synthetic_map()


## A blank map resource that is guaranteed to carry a [code]control_points[/code] property:
## the shipped [MapResource] once it declares one, and a subclass generated at RUNTIME into a
## temp path that adds it until then.
##
## Generated rather than written as an inner class on purpose. An inner
## [code]extends MapResource ... var control_points[/code] would stop COMPILING the day the
## property lands on the parent (a subclass may not redeclare a parent member), taking the
## whole suite red at the exact moment the feature became real. Generated, the branch simply
## stops being taken.
func _new_map() -> MapResource:
	var probe := MapResource.new()
	if "control_points" in probe:
		return probe

	var file := FileAccess.open(TEMP_SCRIPT_PATH, FileAccess.WRITE)
	if file == null:
		return null
	file.store_string("extends MapResource\n\nvar control_points: Array = []\n")
	file.close()

	var script := load(TEMP_SCRIPT_PATH) as GDScript
	if script == null or not script.can_instantiate():
		return null
	return script.new() as MapResource


## A 7x7 map declaring two bases and two control points, and nothing else -- no lanes, no
## mode, no siege controller. Mirrors MapLoader.create_default_map's shape.
func _synthetic_map() -> MapResource:
	var map := _new_map()
	if map == null:
		return null
	map.map_name = "Control Point Probe"
	map.width = 7
	map.height = 7
	map.create_default_layout()
	map.set_unit_spawn_at_position(Vector2i(0, 0), 0, "WARRIOR")
	map.set_unit_spawn_at_position(Vector2i(6, 6), 1, "WARRIOR")
	map.set_base_cell(0, Vector2i(0, 0))
	map.set_base_cell(1, Vector2i(6, 6))
	map.set("control_points", [Vector2i(3, 3), Vector2i(1, 5)])
	return map


## The map's OWN declared control-point array, read raw. Deliberately not filtered here: the
## point of comparing against it is that it is the input, not a second copy of production's
## derivation of the input.
func _raw_points(map) -> Array:
	if map == null:
		return []
	var raw = map.get("control_points")
	return raw if raw is Array else []


func _markers_node() -> ObjectiveMarkers:
	if _map_node == null or not is_instance_valid(_map_node):
		return null
	return _map_node.get_node_or_null(MARKERS.NODE_NAME) as ObjectiveMarkers


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child in node.get_children():
		found.append_array(_descendants(child))
	return found


## Mount [param node] under the markers and remember it, so after_each takes it away again.
func _inject(node: Node, parent: Node) -> Node:
	parent.add_child(node)
	_injected.append(node)
	return node


# =============================================================================
# Doubles
# =============================================================================

## A stand-in mode controller. Duck-typed exactly like [SiegeController] will be: the markers
## never reference that class, they only ask whatever object answers these method names.
class StubMode extends Node:
	var owners: Dictionary = {}
	var contested: Dictionary = {}
	var announces: bool = false

	func control_point_owner(cell: Vector2i) -> int:
		return int(owners.get(cell, -1))

	func control_point_contested(cell: Vector2i) -> bool:
		return bool(contested.get(cell, false))

	func announces_control_points() -> bool:
		return announces


## The shape [SiegeController] actually landed with: ownership, a CLAIMER ID (the midpoint
## mirror of capturing_by) rather than a boolean, and its own announce entry point.
class SiegeShapedMode extends Node:
	var owners: Dictionary = {}
	var claimers: Dictionary = {}

	func control_point_owner(cell: Vector2i) -> int:
		return int(owners.get(cell, -1))

	func control_point_claimer(cell: Vector2i) -> int:
		return int(claimers.get(cell, -1))

	func _announce_control_point(_previous_owner: int) -> void:
		pass


## A controller from a build that knows nothing about control points -- it can answer the base
## banners' capture question and NOTHING else. The markers must degrade to silence.
class MuteMode extends Node:
	func capturing_by() -> int:
		return -1


## Records what the markers push at the battle's announcer, in order.
class RecordingAnnouncer extends Node:
	var lines: Array[Dictionary] = []

	func announce(text: String, sub: String = "", color: Color = Color.WHITE) -> void:
		lines.append({"text": text, "sub": sub, "color": color})


## A map-shaped double for the PURE planning tests. Not a MapResource: [method
## ObjectiveMarkers.plan_control_points] reads one property through get(), and proving that is
## the whole contract means handing it something that is only that contract.
class FakeMap extends RefCounted:
	var width: int = 10
	var height: int = 10
	var base_cells: Dictionary = {}
	var control_points: Array = []


# =============================================================================
# 1. The markers exist, one per declared cell, where the map said
# =============================================================================

func test_every_declared_control_point_gets_its_own_marker() -> void:
	if _map_res == null:
		pending("no map resource carrying control_points could be built")
		return
	var markers := _markers_node()
	assert_not_null(markers, "a map that declares control points mounts the marker layer")
	if markers == null:
		return

	var declared: Array = _raw_points(_map_res)
	assert_gt(declared.size(), 0, "the fixture map really does declare control points")
	assert_eq(markers.control_point_count(), declared.size(),
		"one marker per declared control point -- no more, no fewer")

	for index in range(markers.control_point_count()):
		var marker: Node3D = markers.control_point_marker(index)
		assert_not_null(marker, "control point %d carries a marker" % index)
		if marker == null:
			continue
		var cell: Vector2i = marker.get_meta("cell")
		assert_true(declared.has(cell),
			"marker %d stands on a cell the MAP declared (%s)" % [index, str(cell)])
		assert_almost_eq(marker.position.x, float(cell.x) * 2.0 + 1.0, 0.001,
			"and on that cell's centre in X")
		assert_almost_eq(marker.position.z, float(cell.y) * 2.0 + 1.0, 0.001,
			"and on its centre in Z")


func test_the_marker_order_is_the_authored_order_on_every_peer() -> void:
	var markers := _markers_node()
	if markers == null:
		pending("no markers mounted")
		return
	var cells: Array[Vector2i] = markers.control_point_cells()
	var names: Array[String] = []
	for child in markers.get_children():
		if String(child.name).begins_with("ControlPoint"):
			names.append(String(child.name))

	assert_eq(names.size(), cells.size(), "every planned point produced exactly one child node")
	for index in range(cells.size()):
		assert_eq(names[index], "ControlPoint%d" % index,
			"node %d is named for its authored index -- two peers build the same tree" % index)
		assert_eq(markers.control_point_marker(index).get_meta("cell"), cells[index],
			"and holds the cell the plan put at that index")


func test_planning_is_pure_data_and_drops_junk_duplicates_and_strays() -> void:
	var fake := FakeMap.new()
	fake.width = 6
	fake.height = 6
	fake.control_points = [
		Vector2i(1, 1),
		Vector2i(1, 1),        # duplicate: two markers on one cell would z-fight forever
		Vector2i(9, 9),        # out of bounds
		Vector2i(-1, 2),       # negative
		"not a cell",          # junk
		Vector2i(4, 5),
	]
	var plan: Array[Dictionary] = MARKERS.plan_control_points(fake)
	assert_eq(plan.size(), 2, "only the two usable cells survive -- junk is skipped, not fatal")
	assert_eq(plan[0]["cell"], Vector2i(1, 1), "the first authored cell keeps the first slot")
	assert_eq(plan[1]["cell"], Vector2i(4, 5), "and the second the second")
	assert_eq(plan[0]["index"], 0, "indices are the marker's own, packed, 0-based")
	assert_eq(plan[1]["index"], 1, "and consecutive")

	var again: Array[Dictionary] = MARKERS.plan_control_points(fake)
	assert_eq(again[0]["cell"], plan[0]["cell"],
		"planning the same map twice plans the same cells -- no RNG anywhere in it")
	assert_eq(again[1]["cell"], plan[1]["cell"], "in the same order")

	var empty := FakeMap.new()
	assert_eq(MARKERS.plan_control_points(empty).size(), 0,
		"a map that declares none pays nothing")
	assert_eq(MARKERS.plan_control_points(null).size(), 0, "and neither does no map at all")


# =============================================================================
# 2. Smaller than a base banner
# =============================================================================

func test_a_control_point_marker_is_visibly_smaller_than_a_base_banner() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0:
		pending("no control point markers mounted")
		return

	assert_lt(markers.control_point_top_height(), markers.top_height(),
		"a control point is SHORTER than a base banner -- that is how the player tells the "
		+ "lesser objective from the one that ends the battle")
	assert_almost_eq(markers.control_point_top_height(),
		markers.pole_height * markers.control_point_scale, 0.001,
		"and it is exactly the authored fraction of the mast, not a hand-picked second number")

	var marker: Node3D = markers.control_point_marker(0)
	var pole := marker.get_node("Pole") as MeshInstance3D
	var pole_mesh := pole.mesh as BoxMesh
	assert_almost_eq(pole_mesh.size.y, markers.pole_height * markers.control_point_scale, 0.001,
		"the mast really is built at the reduced height (primitives, not a scene)")

	var pennant := marker.get_node("Banner/Pennant") as MeshInstance3D
	var prism := pennant.mesh as PrismMesh
	assert_almost_eq(prism.size.x, markers.banner_width * markers.control_point_scale, 0.001,
		"and the pennant is scaled with it in width")
	assert_almost_eq(prism.size.y, markers.banner_height * markers.control_point_scale, 0.001,
		"and in height")

	assert_null(marker.get_node_or_null("Banner/Finial"),
		"a control point wears the pennant ONLY -- no finial gem, which is the base banner's")
	assert_null(marker.get_node_or_null("Plinth"),
		"and no plinth: its silhouette is a strict subset of the banner's")

	var banner := marker.get_node("Banner") as Node3D
	assert_almost_eq(banner.position.y, markers.control_point_top_height(), 0.001,
		"the pennant hangs at the top of its own (short) mast")


# =============================================================================
# 3. Neutral until owned, then the owner's colour, on its own materials
# =============================================================================

func test_an_unclaimed_control_point_stands_neutral_stone() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0:
		pending("no control point markers mounted")
		return

	for index in range(markers.control_point_count()):
		assert_eq(markers.control_point_owner_shown(index), -1,
			"control point %d starts owned by nobody" % index)
		assert_eq(markers.control_point_tint(index), markers.neutral_stone,
			"so it wears the neutral stone tone, not a team colour")
		assert_ne(markers.control_point_tint(index), MARKERS.color_for_player(0),
			"which is nobody's colour -- it cannot be read as player 1's")
		assert_ne(markers.control_point_tint(index), MARKERS.color_for_player(1),
			"nor as player 2's")


func test_every_marker_holds_its_own_duplicated_materials() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() < 2:
		pending("need two control point markers to prove they are not sharing")
		return

	var mat_a := (markers.control_point_marker(0).get_node("Banner/Pennant") as MeshInstance3D) \
		.material_override
	var mat_b := (markers.control_point_marker(1).get_node("Banner/Pennant") as MeshInstance3D) \
		.material_override
	var pole_a := (markers.control_point_marker(0).get_node("Pole") as MeshInstance3D) \
		.material_override

	assert_not_null(mat_a, "the first point's pennant carries a material")
	assert_ne(mat_a, mat_b,
		"the two points hold DUPLICATED materials -- re-tinting one can never recolour the other")
	assert_ne(mat_a, pole_a, "and a marker's mast and pennant are separate materials too")

	var base_marker: Node3D = markers.marker_for(0)
	if base_marker != null:
		var base_mat := (base_marker.get_node("Banner/Pennant") as MeshInstance3D).material_override
		assert_ne(mat_a, base_mat,
			"and no control point ever shares a material with a BASE banner")


func test_a_change_of_hands_retints_that_point_and_only_that_point() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() < 2:
		pending("need two control point markers")
		return

	var cells: Array[Vector2i] = markers.control_point_cells()
	var stub: StubMode = _inject(StubMode.new(), markers) as StubMode
	stub.name = "StubMode"
	markers.mode_controller_path = NodePath("StubMode")

	# Baseline: the mode reports nobody, so nothing moves.
	markers.refresh_control_points()
	assert_eq(markers.control_point_owner_shown(0), -1, "nobody holds the first point yet")

	stub.owners[cells[0]] = 0
	markers.refresh_control_points()

	assert_eq(markers.control_point_owner_shown(0), 0, "the mode says player 0 took it")
	assert_eq(markers.control_point_tint(0), MARKERS.color_for_player(0),
		"so the marker wears player 0's own team colour -- the same one the units wear")
	assert_eq(markers.control_point_owner_shown(1), -1, "the other point did not change hands")
	assert_eq(markers.control_point_tint(1), markers.neutral_stone,
		"and is still standing neutral stone")

	# It changes hands again, and then is neutralised.
	stub.owners[cells[0]] = 1
	markers.refresh_control_points()
	assert_eq(markers.control_point_tint(0), MARKERS.color_for_player(1),
		"a second change of hands re-tints to the NEW owner")

	stub.owners[cells[0]] = -1
	markers.refresh_control_points()
	assert_eq(markers.control_point_owner_shown(0), -1, "losing it to nobody neutralises it")
	assert_eq(markers.control_point_tint(0), markers.neutral_stone,
		"and puts the stone tone back")


func test_the_mast_is_tinted_with_the_pennant_but_darker() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0:
		pending("no control point markers mounted")
		return
	var cells: Array[Vector2i] = markers.control_point_cells()
	var stub: StubMode = _inject(StubMode.new(), markers) as StubMode
	stub.name = "StubMode"
	markers.mode_controller_path = NodePath("StubMode")
	markers.refresh_control_points()

	stub.owners[cells[0]] = 0
	markers.refresh_control_points()

	var pole_mat := (markers.control_point_marker(0).get_node("Pole") as MeshInstance3D) \
		.material_override as StandardMaterial3D
	var owner_color: Color = MARKERS.color_for_player(0)
	assert_almost_eq(pole_mat.albedo_color.r, owner_color.r * markers.pole_shade, 0.001,
		"the mast keeps the same darkened fraction of the tint a base banner's mast does")
	assert_eq(pole_mat.emission, owner_color,
		"and glows the owner's colour, so the whole marker reads as one object")


# =============================================================================
# 4. Contested points escalate, and a mute mode is silent
# =============================================================================

func test_a_claim_in_progress_pulses_faster_and_brighter() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() < 2:
		pending("need two control point markers")
		return

	var cells: Array[Vector2i] = markers.control_point_cells()
	var stub: StubMode = _inject(StubMode.new(), markers) as StubMode
	stub.name = "StubMode"
	markers.mode_controller_path = NodePath("StubMode")
	markers.refresh_control_points()

	var calm_seconds: float = float(markers._cp_state[0]["bob_seconds"])
	var calm_emission: float = float(markers._cp_state[0]["emission_peak"])
	assert_false(markers.is_control_point_urgent(0), "nothing is being claimed, so nothing is urgent")

	stub.contested[cells[0]] = true
	markers.refresh_control_points()

	assert_true(markers.is_control_point_urgent(0), "the point being claimed escalates")
	assert_false(markers.is_control_point_urgent(1), "and the untouched one keeps bobbing calmly")
	assert_lt(float(markers._cp_state[0]["bob_seconds"]), calm_seconds,
		"the contested marker pulses FASTER")
	assert_gt(float(markers._cp_state[0]["emission_peak"]), calm_emission,
		"and BRIGHTER, so the cell deciding the match is the loudest thing on the board")

	stub.contested[cells[0]] = false
	markers.refresh_control_points()
	assert_false(markers.is_control_point_urgent(0), "a lapsed claim calms it back down")
	assert_almost_eq(float(markers._cp_state[0]["bob_seconds"]), calm_seconds, 0.0001,
		"at exactly the rate it started at")


func test_the_real_siege_shaped_controller_drives_the_markers_as_it_is() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() < 2:
		pending("need two control point markers")
		return

	var cells: Array[Vector2i] = markers.control_point_cells()
	var siege: SiegeShapedMode = _inject(SiegeShapedMode.new(), markers) as SiegeShapedMode
	siege.name = "SiegeShaped"
	markers.mode_controller_path = NodePath("SiegeShaped")
	markers.refresh_control_points()

	# A claim goes in flight: the mode reports a claimer id, not a boolean.
	siege.claimers[cells[0]] = 1
	markers.refresh_control_points()
	assert_true(markers.is_control_point_urgent(0),
		"a claimer id is read as 'somebody is taking this' -- the marker escalates")
	assert_false(markers.is_control_point_urgent(1), "and the untouched point stays calm")

	# It lands.
	siege.claimers.erase(cells[0])
	siege.owners[cells[0]] = 1
	markers.refresh_control_points()
	assert_false(markers.is_control_point_urgent(0), "a resolved claim stops the urgent pulse")
	assert_eq(markers.control_point_tint(0), MARKERS.color_for_player(1),
		"and the point now flies the colour of the side that took it")


func test_the_line_belongs_to_the_mode_when_the_mode_has_one() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0:
		pending("no control point markers mounted")
		return

	var cells: Array[Vector2i] = markers.control_point_cells()
	var siege: SiegeShapedMode = _inject(SiegeShapedMode.new(), markers) as SiegeShapedMode
	siege.name = "SiegeShaped"
	markers.mode_controller_path = NodePath("SiegeShaped")
	var rec: RecordingAnnouncer = _inject(RecordingAnnouncer.new(), markers) as RecordingAnnouncer
	rec.name = "Recorder"
	markers.announcer_path = NodePath("Recorder")

	markers.refresh_control_points()
	siege.owners[cells[0]] = 0
	markers.refresh_control_points()

	assert_eq(markers.control_point_tint(0), MARKERS.color_for_player(0),
		"the marker layer still re-tints -- that half is always its job")
	assert_eq(rec.lines.size(), 0,
		"but a mode that announces claims itself owns the LINE, and the player hears it once")


func test_a_mode_that_knows_nothing_of_control_points_leaves_them_neutral_and_calm() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0:
		pending("no control point markers mounted")
		return

	var mute: MuteMode = _inject(MuteMode.new(), markers) as MuteMode
	mute.name = "MuteMode"
	markers.mode_controller_path = NodePath("MuteMode")

	markers.refresh_control_points()
	markers.refresh_control_points()

	for index in range(markers.control_point_count()):
		assert_eq(markers.control_point_owner_shown(index), -1,
			"a controller that cannot answer owner leaves point %d neutral" % index)
		assert_false(markers.is_control_point_urgent(index),
			"and one that cannot answer contested leaves it calm")


func test_with_no_mode_controller_at_all_nothing_errors() -> void:
	var lone = autofree(MARKERS.new())
	lone.refresh_control_points()
	assert_eq(lone.control_point_count(), 0,
		"a marker set built from no map shows no control points, and asking it costs nothing")
	assert_eq(lone.control_point_owner_shown(0), -1, "an unknown index answers neutral, not an error")
	assert_false(lone.is_control_point_urgent(0), "and is never urgent")


# =============================================================================
# 5. The claim line
# =============================================================================

func test_the_claim_line_is_written_from_the_local_players_side() -> void:
	var mine: Dictionary = MARKERS.claim_line("Midpoint", -1, 0, 0)
	assert_eq(mine["text"], "Midpoint claimed!", "taking a point is a claim, in the player's voice")
	assert_eq(mine["color"], ActionAnnouncer.ALLY_COLOR, "tinted like every other friendly line")

	var theirs: Dictionary = MARKERS.claim_line("Midpoint", 0, 1, 0)
	assert_eq(theirs["text"], "Midpoint lost!", "and losing one is a loss, not a neutral report")
	assert_eq(theirs["color"], ActionAnnouncer.ENEMY_COLOR, "tinted like every other enemy line")

	var stolen: Dictionary = MARKERS.claim_line("Midpoint", -1, 1, 0)
	assert_eq(stolen["text"], "Midpoint lost!",
		"an enemy taking an unowned point is the same news to the player: it works against them")

	var freed: Dictionary = MARKERS.claim_line("Midpoint", 1, -1, 0)
	assert_eq(freed["text"], "Midpoint neutral", "and a point knocked back to nobody says so")


func test_with_no_local_side_the_line_takes_no_side() -> void:
	var line: Dictionary = MARKERS.claim_line("Point 2", -1, 1, -1)
	assert_eq(line["text"], "Point 2 claimed",
		"a replay or spectator gets a statement of fact, never 'lost!'")
	assert_eq(line["sub"], "Player 2", "and is told WHO took it, since it is nobody's side")
	assert_eq(line["color"], ActionAnnouncer.NEUTRAL_COLOR, "in the neutral tint")


func test_a_point_is_named_for_the_map_that_declares_it() -> void:
	var markers := _markers_node()
	if markers == null:
		pending("no markers mounted")
		return
	if markers.control_point_count() == 1:
		assert_eq(markers.control_point_name(0), markers.control_point_label,
			"a lone control point gets the authored single-point name")
	else:
		assert_eq(markers.control_point_name(0), markers.control_point_label_format % 1,
			"several points are numbered, 1-based, so the player never reads an index")
		assert_ne(markers.control_point_name(0), markers.control_point_name(1),
			"and two points never announce under the same name")


func test_a_change_of_hands_announces_once_through_the_battles_own_announcer() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0:
		pending("no control point markers mounted")
		return

	var cells: Array[Vector2i] = markers.control_point_cells()
	var stub: StubMode = _inject(StubMode.new(), markers) as StubMode
	stub.name = "StubMode"
	markers.mode_controller_path = NodePath("StubMode")
	var rec: RecordingAnnouncer = _inject(RecordingAnnouncer.new(), markers) as RecordingAnnouncer
	rec.name = "Recorder"
	markers.announcer_path = NodePath("Recorder")

	markers.refresh_control_points()
	assert_eq(rec.lines.size(), 0, "the baseline poll is silent -- nothing changed hands")

	stub.owners[cells[0]] = 0
	markers.refresh_control_points()
	assert_eq(rec.lines.size(), 1, "one change of hands is exactly one line")
	assert_eq(String(rec.lines[0]["text"]), "%s claimed!" % markers.control_point_name(0),
		"and it names the point the player just took")

	markers.refresh_control_points()
	markers.refresh_control_points()
	assert_eq(rec.lines.size(), 1,
		"polling again while nothing moves never repeats the line -- the poll is not the event")

	stub.owners[cells[0]] = 1
	markers.refresh_control_points()
	assert_eq(rec.lines.size(), 2, "losing it is its own line")
	assert_eq(String(rec.lines[1]["text"]), "%s lost!" % markers.control_point_name(0),
		"in the losing voice")


func test_a_point_that_opens_already_owned_never_announces_a_claim() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0:
		pending("no control point markers mounted")
		return

	var cells: Array[Vector2i] = markers.control_point_cells()
	var stub: StubMode = _inject(StubMode.new(), markers) as StubMode
	stub.name = "StubMode"
	stub.owners[cells[0]] = 1
	markers.mode_controller_path = NodePath("StubMode")
	var rec: RecordingAnnouncer = _inject(RecordingAnnouncer.new(), markers) as RecordingAnnouncer
	rec.name = "Recorder"
	markers.announcer_path = NodePath("Recorder")

	markers.refresh_control_points()

	assert_eq(markers.control_point_tint(0), MARKERS.color_for_player(1),
		"the opening state is PAINTED -- the player sees who holds it from turn one")
	assert_eq(rec.lines.size(), 0,
		"but is never ANNOUNCED: nobody claimed anything, the battle merely started")


func test_the_marker_layer_stays_quiet_when_the_mode_announces_claims_itself() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0:
		pending("no control point markers mounted")
		return

	var cells: Array[Vector2i] = markers.control_point_cells()
	var stub: StubMode = _inject(StubMode.new(), markers) as StubMode
	stub.name = "StubMode"
	stub.announces = true
	markers.mode_controller_path = NodePath("StubMode")
	var rec: RecordingAnnouncer = _inject(RecordingAnnouncer.new(), markers) as RecordingAnnouncer
	rec.name = "Recorder"
	markers.announcer_path = NodePath("Recorder")

	markers.refresh_control_points()
	stub.owners[cells[0]] = 0
	markers.refresh_control_points()

	assert_eq(markers.control_point_tint(0), MARKERS.color_for_player(0),
		"the marker still re-tints -- that is the marker layer's job either way")
	assert_eq(rec.lines.size(), 0,
		"but the LINE is the mode's, and the player hears it once rather than twice")


# =============================================================================
# 6. It is decoration, and nothing else
# =============================================================================

func test_the_control_points_add_no_board_cells() -> void:
	if _map_res == null:
		pending("no fixture map")
		return
	var tiles := _map_node.get_node("Tiles")
	assert_eq(tiles.get_child_count(), _map_res.width * _map_res.height,
		"the board is still width x height tiles -- the control point markers contributed none")


func test_the_markers_are_a_sibling_of_the_tile_container() -> void:
	if _map_res == null:
		pending("no fixture map")
		return
	var tiles := _map_node.get_node_or_null("Tiles")
	assert_not_null(tiles, "the playable tile container is there")
	if tiles == null:
		return
	assert_null(tiles.get_node_or_null(MARKERS.NODE_NAME),
		"the markers live OUTSIDE Tiles -- the camera fits that container's children")


func test_a_control_point_cell_is_still_exactly_the_terrain_the_map_authored() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0 or not CombatServices:
		pending("no control point markers, or no CombatServices autoload")
		return
	var cell: Vector2i = markers.control_point_cells()[0]
	assert_not_null(CombatServices.tile_at(cell),
		"the control point cell is still registered terrain, exactly as before")
	assert_eq(CombatServices.tile_effects_at(cell).size(), 0,
		"and the marker standing on it registered no tile effect of its own")


func test_the_control_point_markers_carry_no_collider() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0:
		pending("no control point markers mounted")
		return
	var colliders: Array[Node] = []
	for index in range(markers.control_point_count()):
		for node in _descendants(markers.control_point_marker(index)):
			if node is CollisionObject3D:
				colliders.append(node)
	assert_eq(colliders.size(), 0,
		"nothing in a control point marker can be hit by a physics ray, now or by a future picker")


func test_a_control_point_marker_is_a_handful_of_nodes() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0:
		pending("no control point markers mounted")
		return
	var nodes: Array[Node] = _descendants(markers.control_point_marker(0))
	assert_lte(nodes.size(), 4,
		"a control point costs root + mast + pivot + pennant and nothing more (got %d)"
			% nodes.size())


func test_with_animations_off_the_markers_are_lit_but_still() -> void:
	var markers := _markers_node()
	if markers == null or markers.control_point_count() == 0:
		pending("no control point markers mounted")
		return
	if typeof(GameSettings) != TYPE_OBJECT or GameSettings == null:
		pending("no GameSettings autoload to switch animations off with")
		return

	# Assigned through the guard, never through the setter -- that one writes
	# user://settings.cfg, i.e. the player's real settings file. Set BOTH ways explicitly: the
	# machine running the suite may have animations switched off in its own settings, and an
	# assertion that depends on that is a property of the machine rather than of the code.
	_guard.set_setting("animations_enabled", true)
	markers.generate(_map_res)
	assert_ne(markers._cp_state[0]["tween"], null,
		"with animations ON the marker really is running a bob")

	_guard.set_setting("animations_enabled", false)
	markers.generate(_map_res)

	assert_eq(markers._cp_state[0]["tween"], null,
		"with animations OFF nothing is tweening")
	var banner := markers.control_point_marker(0).get_node("Banner") as Node3D
	assert_almost_eq(banner.position.y, markers.control_point_top_height(), 0.001,
		"the pennant is parked at its resting pose -- still perfectly legible, just not moving")


# =============================================================================
# 7. Lifecycle: built with the map, freed with the map
# =============================================================================

func test_the_control_point_markers_are_freed_with_the_map() -> void:
	if _lifecycle.is_empty():
		pending("no fixture map to run the lifecycle on")
		return
	assert_true(bool(_lifecycle["mounted"]), "loading the map mounted a marker layer")
	assert_gt(int(_lifecycle["points"]), 0, "carrying control point markers")
	assert_true(bool(_lifecycle["node_after_clear_is_null"]),
		"clearing the map takes them with it -- no orphaned mast survives a reload")
	assert_true(bool(_lifecycle["loader_ref_after_clear_is_null"]),
		"and the loader drops its reference to them")


func test_reloading_never_stacks_two_sets_of_control_points() -> void:
	if _lifecycle.is_empty():
		pending("no fixture map to run the lifecycle on")
		return
	assert_eq(int(_lifecycle["sets_after_reload"]), 1,
		"a second load replaces the marker layer rather than planting another on top")
	assert_eq(int(_lifecycle["points_after_reload"]), _raw_points(_map_res).size(),
		"so the board still shows exactly one marker per declared control point")


func test_a_map_that_declares_neither_bases_nor_points_mounts_nothing() -> void:
	if _lifecycle.is_empty():
		pending("no fixture map to run the lifecycle on")
		return
	assert_false(bool(_lifecycle["bare_declares_bases"]), "the default map declares no bases")
	assert_false(bool(_lifecycle["bare_declares_points"]), "and no control points")
	assert_false(bool(_lifecycle["bare_mounted"]),
		"so it pays nothing -- not even an empty marker node")


## Drive the whole marker LIFECYCLE once and write down what happened: mount, reload, clear,
## and what a map declaring neither bases nor control points gets. Every board it stands up is
## freed before it returns. See [member _lifecycle] for why this is not done in the tests.
func _observe_lifecycle() -> Dictionary:
	var out: Dictionary = {}
	if _map_res == null:
		return out

	var board := _mount_board("LifecycleBoard")
	var map_node: Node3D = board["map_node"]
	var loader: MapLoader = board["loader"]
	loader.load_map(_map_res, map_node)

	var mounted := map_node.get_node_or_null(MARKERS.NODE_NAME) as ObjectiveMarkers
	out["mounted"] = mounted != null
	out["points"] = mounted.control_point_count() if mounted != null else -1

	loader.load_map(_map_res, map_node)
	var sets: int = 0
	var points: int = 0
	for child in map_node.get_children():
		if child.name == MARKERS.NODE_NAME:
			sets += 1
			points += (child as ObjectiveMarkers).control_point_count()
	out["sets_after_reload"] = sets
	out["points_after_reload"] = points

	loader.clear_current_map()
	out["node_after_clear_is_null"] = map_node.get_node_or_null(MARKERS.NODE_NAME) == null
	out["loader_ref_after_clear_is_null"] = loader.objective_markers == null
	_free_board(board)

	# ...and the map that declares neither, which must pay nothing at all.
	var bare := MapLoader.create_default_map()
	out["bare_declares_bases"] = not bare.base_cells.is_empty()
	out["bare_declares_points"] = not _raw_points(bare).is_empty()
	var bare_board := _mount_board("LifecycleBareBoard")
	(bare_board["loader"] as MapLoader).load_map(bare, bare_board["map_node"])
	out["bare_mounted"] = (bare_board["map_node"] as Node3D) \
		.get_node_or_null(MARKERS.NODE_NAME) != null
	_free_board(bare_board)

	return out


## A fresh root-mounted board (scene root + "Map" + a loader), as { root, map_node, loader }.
func _mount_board(root_name: String) -> Dictionary:
	var scene_root := Node3D.new()
	scene_root.name = root_name
	get_tree().root.add_child(scene_root)

	var map_node := Node3D.new()
	map_node.name = "Map"
	scene_root.add_child(map_node)

	var loader := MapLoader.new()
	map_node.add_child(loader)
	return { "root": scene_root, "map_node": map_node, "loader": loader }


func _free_board(board: Dictionary) -> void:
	var scene_root: Node3D = board["root"]
	if scene_root == null or not is_instance_valid(scene_root):
		return
	if scene_root.get_parent() != null:
		scene_root.get_parent().remove_child(scene_root)
	scene_root.free()
