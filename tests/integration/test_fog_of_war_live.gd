extends GutTest

## FOG OF WAR on a REAL board, under the REAL battle HUD.
##
## Everything asserted here is something the player would see (or fail to see) on screen:
## the number of shrouded cells and where they sit, whether an enemy's model and world-space
## health bar are actually rendered, whether the cursor and the hover card will admit that
## something is standing there, what the battle log says, and what the turn-queue chip
## reveals. The HUD assertions run against the REAL mounted GameUILayout.tscn -- its live
## [BattleLog], [TurnQueue] and [ActionAnnouncer] nodes -- per the project's standing rule
## that battle UI is proven on the mounted scene, never on a helper's return value.
##
## THE VISION ORACLE IS A STUB ([FogDoubles.StubVision]), injected through
## [method FogOfWarOverlay.set_vision_override]. The core that decides who sees what lands
## separately; this suite pins the PRESENTATION contract against an oracle it controls, so a
## failure here is always a failure of the look or the refusal, never of the vision maths.
##
## The board fixture (a live "Map" root with real character-backed [Unit]s and a
## [CombatServices] rebuild) follows `integration/test_move_fx_live.gd`, with one addition:
## it stands up a real CURRENT SCENE. GUT's command-line runner adds itself to
## `get_tree().root` and never sets `current_scene`, so under it that property is null -- and
## null is exactly the value that makes [board/cursor/cursor.gd] find no units,
## [method Unit._find_visual_manager] build no health bars, and the announcer lookup fail.
## Testing those against a null-scene tree would prove nothing about the real battle, so this
## suite creates a scene root, points `current_scene` at it for the duration of one test, and
## restores it from `after_each` (which GUT runs on the failure path too).

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const FogDoubles := preload("res://tests/helpers/fog_doubles.gd")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const LAYOUT: PackedScene = preload("res://game/ui/layout/GameUILayout.tscn")
const CURSOR_SCENE: PackedScene = preload("res://board/cursor/cursor.tscn")
const FOG := preload("res://game/visuals/FogOfWarOverlay.gd")
const DAMAGE_NUMBERS := preload("res://game/visuals/DamageNumbers.gd")
const MOVE_FX := preload("res://game/visuals/MoveFXDispatcher.gd")

const ALLY_ID: StringName = &"test_fog_ally"
const FOE_ID: StringName = &"test_fog_foe"

## The fixture board is the SHIPPED default size of `board/Grid.tres` (5x5), and every cell
## this suite names lives inside it.
##
## Deliberately NOT resized. `Grid.tres` is a shared preloaded resource that MapLoader sizes
## per map, so a suite that resized it would be mutating global state for every later suite
## in the run (tests/README rule 3) -- and under GUT the resize does not even reach the
## instance [CombatServices] holds, because GUT loads test scripts with the resource cache
## ignored. Fitting the fixture to the real default removes both problems.
const COLS: int = 5
const ROWS: int = 5

const ALLY_CELL := Vector2i(0, 0)
const FOE_CELL := Vector2i(3, 3)

## Untyped on purpose -- see tests/README.md, rule 3.
var _guard

## The board [Grid], reached through [CombatServices] rather than preloaded here: GUT loads
## test scripts with the resource cache IGNORED, so a `preload("res://board/Grid.tres")` in
## this file resolves to a DIFFERENT Grid instance from the one the overlay sweeps. Always
## reach a shared resource through its owner.
var GRID = CombatServices.GRID

## The stand-in battle scene everything mounts under -- see the class doc. Freed (with every
## child) from after_each, so nothing here can orphan.
var _scene_root: Node3D
var _prev_scene: Node = null

var _map_root: Node3D
var _fog: FogOfWarOverlay
var _vision
var _ally: Unit
var _foe: Unit
var _saved_players: Array = []
var _saved_index: int = 0


func before_each() -> void:
	_guard = Guard.new()
	# Assigned through the guard, never the setter (which persists to user://settings.cfg).
	_guard.set_setting("animations_enabled", true)
	_guard.set_setting("battle_speed", 1.0)
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)

	_saved_players = PlayerManager.players.duplicate()
	_saved_index = PlayerManager.current_player_index

	CombatServices.clear()
	FogOfWarOverlay.reset_for_tests()
	_map_root = null
	_fog = null
	_vision = null
	_ally = null
	_foe = null

	# A real current scene, so every production lookup that goes through it is exercised
	# for real rather than short-circuited on null (see the class doc).
	_scene_root = Node3D.new()
	_scene_root.name = "FogBattleScene"
	get_tree().root.add_child(_scene_root)
	_prev_scene = get_tree().current_scene
	get_tree().current_scene = _scene_root

	_install_test_characters()


func after_each() -> void:
	FogOfWarOverlay.reset_for_tests()
	ReplayPlayback.end_playback()
	CombatServices.clear()
	get_tree().current_scene = _prev_scene
	# Everything this suite mounts lives under the stand-in scene root, so ONE immediate
	# free takes the board, the HUD, the overlay and the lazily-created UnitVisualManager
	# with it. Never queue_free in a test -- GUT counts orphans before the frame ends.
	if _scene_root != null and is_instance_valid(_scene_root):
		get_tree().root.remove_child(_scene_root)
		_scene_root.free()
	_scene_root = null
	_map_root = null
	_ally = null
	_foe = null
	CharacterLibrary.clear_cache()
	PlayerManager.players.assign(_saved_players)
	PlayerManager.current_player_index = _saved_index
	_guard.restore()


# =============================================================================
# Fixture
# =============================================================================

func _install_test_characters() -> void:
	CharacterLibrary._cache[ALLY_ID] = _make_character(ALLY_ID, "Vineweave")
	CharacterLibrary._cache[FOE_ID] = _make_character(FOE_ID, "Blightcap")


func _make_character(id: StringName, display: String) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = id
	c.display_name = display
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 100
	c.base_attack = 20
	c.base_defense = 5
	c.base_magic = 10
	c.base_magic_defense = 5
	c.base_speed = 11
	c.base_movement = 3
	c.attack_range = 1
	return c


func _cell_to_world(cell: Vector2i) -> Vector3:
	return BoardAdapter.new(GRID, []).cell_to_world(cell)


func _spawn(character_id: StringName, cell: Vector2i, owner: Player, container: Node3D) -> Unit:
	var character := CharacterLibrary.get_character(character_id)
	if character == null:
		return null
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character  # before add_child: _ready() builds stats from it
	unit.position = _cell_to_world(cell)
	container.add_child(unit)
	owner.add_unit(unit)
	return unit


## A live two-unit board, seated as a solo battle (human 0 vs bot 1), with the fog overlay
## NOT yet mounted -- the caller injects its vision stub first, so the overlay's very first
## refresh already sees the oracle it is meant to obey.
##
## Returns false when the synthetic characters cannot be built, which callers treat as skip.
func _build_board() -> bool:
	if _scene_root == null:
		return false

	_map_root = Node3D.new()
	_map_root.name = "Map"
	_scene_root.add_child(_map_root)

	var p1 := Node3D.new()
	p1.name = "Player1"
	_map_root.add_child(p1)
	var p2 := Node3D.new()
	p2.name = "Player2"
	_map_root.add_child(p2)

	var human := Player.new(0, "You")
	var bot := Player.new(1, "Bot")
	bot.is_ai = true
	PlayerManager.players.assign([human, bot] as Array[Player])
	PlayerManager.current_player_index = 0

	_ally = _spawn(ALLY_ID, ALLY_CELL, human, p1)
	_foe = _spawn(FOE_ID, FOE_CELL, bot, p2)
	if _ally == null or _foe == null:
		return false

	await get_tree().process_frame
	CombatServices.rebuild(_map_root)
	return CombatServices.board() != null


## Install a stub oracle with the board's cell list already loaded.
func _arm_vision() -> FogDoubles.StubVision:
	_vision = FogDoubles.StubVision.new()
	_vision.set_board(COLS, ROWS)
	FogOfWarOverlay.set_vision_override(_vision)
	return _vision


## Mount a layer under the stand-in scene root (not the test node), so anything resolving it
## through `current_scene` -- the cursor's "Map/Player1" lookup, the overlay's announcer and
## turn-queue lookups -- finds it exactly as it would in a battle.
func _mount(node: Node) -> Node:
	_scene_root.add_child(node)
	return node


func _mount_fog() -> FogOfWarOverlay:
	_fog = _mount(FOG.new()) as FogOfWarOverlay
	await get_tree().process_frame
	return _fog


## The batched veil node, or null when nothing is shrouded.
func _shroud() -> MultiMeshInstance3D:
	if _fog == null or not is_instance_valid(_fog):
		return null
	return _fog.get_node_or_null(String(FogOfWarOverlay.SHROUD_NAME)) as MultiMeshInstance3D


## Exactly which cells the veil is drawn over.
##
## Read off the overlay's painted set rather than off the MultiMesh transforms, because
## [method MultiMesh.get_instance_transform] is RenderingServer-backed and returns identity
## for every instance under the headless dummy renderer -- every cell would fold to (0,0) on
## a CI run. The two are tied together by [method _assert_instances_match]: the number of
## RENDERED instances is asserted against the size of this set in every geometry test, so
## "what was painted" can never drift from "what is drawn".
func _shrouded_cells() -> Array[Vector2i]:
	if _fog == null or not is_instance_valid(_fog):
		return [] as Array[Vector2i]
	var out: Array[Vector2i] = _fog.shrouded_cells()
	out.sort()
	return out


## Tie the painted set to the rendered geometry: one MultiMesh instance per shrouded cell.
func _assert_instances_match() -> void:
	var node := _shroud()
	var painted: int = _shrouded_cells().size()
	if painted == 0:
		assert_null(node, "nothing shrouded means no veil node at all")
		return
	assert_not_null(node, "a shrouded set has a veil node")
	if node == null or node.multimesh == null:
		return
	assert_eq(node.multimesh.instance_count, painted,
		"one MultiMesh instance per shrouded cell -- the drawn geometry IS the painted set")


func _mount_hud() -> Control:
	var layout: Control = LAYOUT.instantiate()
	_mount(layout)
	for _i in range(6):
		await get_tree().process_frame
	return layout


# =============================================================================
# FOG OFF -- the layer must be free and invisible
# =============================================================================

func test_with_no_vision_core_the_overlay_draws_nothing_at_all() -> void:
	if not await _build_board():
		pending("could not build the synthetic characters; skipping")
		return
	await _mount_fog()

	assert_eq(_fog.get_child_count(), 0,
		"no vision core mounted: the overlay builds NO geometry -- it is not an empty "
		+ "shroud, there is no shroud node at all")
	assert_false(UnitVisualManager.is_fog_hidden(_ally), "the ally is untouched")
	assert_false(UnitVisualManager.is_fog_hidden(_foe), "the enemy is untouched")
	assert_true(_foe.is_visible_in_tree(), "the enemy renders exactly as it did before fog")


func test_a_core_reporting_fog_off_leaves_the_board_identical() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	var vision := _arm_vision()
	vision.hide_cells(0, [Vector2i(2, 2), Vector2i(3, 3)])
	vision.hide_unit(0, _foe)
	vision.enabled = false  # MapResource.fog_of_war is off for this map
	await _mount_fog()

	assert_eq(_fog.get_child_count(), 0,
		"fog off: no shroud, whatever hidden sets the core is carrying")
	assert_false(UnitVisualManager.is_fog_hidden(_foe),
		"fog off = everything visible -- zero hidden units")
	assert_true(_foe.is_visible_in_tree(), "the enemy is on screen")


# =============================================================================
# THE CELL SHROUD
# =============================================================================

func test_the_shroud_covers_exactly_the_hidden_cells() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	var hidden: Array = [Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 3), Vector2i(4, 4)]
	_arm_vision().hide_cells(0, hidden)
	await _mount_fog()

	var node := _shroud()
	assert_not_null(node, "a shroud was built for the hidden corner")
	if node == null:
		return
	assert_eq(node.multimesh.instance_count, 4,
		"one quad per hidden cell -- exactly the hidden set, nothing rounded up")

	var drawn: Array[Vector2i] = _shrouded_cells()
	var expected: Array[Vector2i] = []
	for cell in hidden:
		expected.append(cell)
	expected.sort()
	assert_eq(drawn, expected, "the veil sits on precisely the cells the core hid")
	_assert_instances_match()


func test_the_shroud_is_one_batched_node_not_one_per_cell() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	# Fog the WHOLE board: the worst case, and the one a per-cell-node implementation would
	# fail on (one MeshInstance3D child per cell instead of one node total).
	var all_cells: Array = []
	for col in range(COLS):
		for row in range(ROWS):
			all_cells.append(Vector2i(col, row))
	_arm_vision().hide_cells(0, all_cells)
	await _mount_fog()

	assert_eq(_fog.get_child_count(), 1,
		"a fully fogged board is ONE node -- MapSurround's merged-mesh economy")
	var node := _shroud()
	assert_not_null(node, "and that node is the batched veil")
	if node != null:
		assert_eq(node.multimesh.instance_count, COLS * ROWS,
			"every cell drawn, as one MultiMesh instance each, in a single draw call")


func test_the_veil_is_warm_dark_and_translucent_so_terrain_stays_readable() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_guard.set_setting("animations_enabled", false)  # no fade tween: read the settled value
	_arm_vision().hide_cells(0, [Vector2i(1, 1)])
	await _mount_fog()

	var node := _shroud()
	assert_not_null(node, "a shroud exists")
	if node == null:
		return
	var mat: StandardMaterial3D = node.material_override as StandardMaterial3D
	assert_not_null(mat, "the veil carries its own material")
	if mat == null:
		return
	assert_lt(mat.albedo_color.a, 1.0,
		"translucent: you know the ground, you just do not know what stands on it")
	assert_gt(mat.albedo_color.a, 0.4, "and opaque enough to actually read as fog")
	assert_gt(mat.albedo_color.r, mat.albedo_color.b,
		"WARM dark, not a black hole punched in the board")


func test_a_core_without_the_batch_call_still_gets_a_shroud() -> void:
	# The overlay prefers VisionSystem.visible_cells(); this core offers only the per-cell
	# probe. The fallback sweep has to produce the identical veil.
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	var probe = FogDoubles.ProbeOnlyVision.new()
	probe.hide_cells([Vector2i(0, 4), Vector2i(1, 4)])
	FogOfWarOverlay.set_vision_override(probe)
	await _mount_fog()

	assert_eq(_shrouded_cells(), [Vector2i(0, 4), Vector2i(1, 4)] as Array[Vector2i],
		"the per-cell fallback shrouds the same set the batch call would have")
	_assert_instances_match()


# =============================================================================
# UNIT HIDING
# =============================================================================

func test_a_hidden_enemy_loses_its_model_and_its_world_health_bar() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_arm_vision().hide_unit(0, _foe)
	await _mount_fog()

	assert_true(UnitVisualManager.is_fog_hidden(_foe), "the enemy is hidden by fog")
	assert_false(_foe.is_visible_in_tree(),
		"nothing of the enemy renders -- model, bar, badges and chips are all children "
		+ "of the unit, so one flag takes the lot")

	var bar: Node = _foe.find_child("HealthBar", true, false)
	if bar == null:
		# The bar is created by UnitVisualManager when the unit takes an owner; if this
		# harness did not get one, the containing assertion above already covers the model.
		gut.p("no HealthBar child on the fixture unit; model assertion stands alone")
	else:
		assert_false((bar as Node3D).is_visible_in_tree(),
			"the world-space health bar goes with it -- a bar floating over empty ground "
			+ "is an outline of exactly the unit we were hiding")

	assert_true(_ally.is_visible_in_tree(), "your own unit is untouched")
	assert_false(UnitVisualManager.is_fog_hidden(_ally), "and is not marked hidden")


func test_hiding_a_unit_does_not_touch_the_model_channel_submerged_owns() -> void:
	# SubmergedStatus hides the MODEL ROOT; fog hides the UNIT above it. Two channels on one
	# parent chain, so they compose through scene-tree visibility and neither strands the
	# other. Proven by showing the model root's OWN flag survives a hide/reveal round trip.
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	var model: Node3D = _foe.get_node_or_null("CharacterModel") as Node3D
	if model == null:
		model = _foe.get_node_or_null("MeshInstance3D") as Node3D
	if model == null:
		pending("fixture unit has no resolvable model root; skipping")
		return

	model.visible = false  # stand in for a live Submerged
	_arm_vision().hide_unit(0, _foe)
	await _mount_fog()
	_vision.show_unit(0, _foe)
	_vision.notify()

	assert_false(model.visible,
		"revealing from fog restored the UNIT's flag and never wrote the model's -- a "
		+ "submerged unit that walks out of the mist is still submerged")
	assert_true(_foe.visible, "while the unit node itself is back")


func test_a_revealed_enemy_pops_back_in_on_vision_changed() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	var vision := _arm_vision()
	vision.hide_unit(0, _foe)
	vision.hide_cells(0, [FOE_CELL])
	await _mount_fog()
	assert_false(_foe.is_visible_in_tree(), "hidden to begin with")

	# Mid-turn reveal: the enemy steps into the light. No turn boundary involved.
	vision.show_unit(0, _foe)
	vision.show_cells(0, [FOE_CELL])
	vision.notify()

	assert_true(_foe.is_visible_in_tree(),
		"vision_changed pops the model straight back in -- mid-enemy-turn, not at the "
		+ "next turn boundary")
	assert_false(_shrouded_cells().has(FOE_CELL), "and its cell clears with it")


# =============================================================================
# PERSPECTIVE SWAPS
# =============================================================================

func test_the_hotseat_swap_flips_the_shroud_on_turn_change() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	# Two HUMAN seats sharing one screen.
	_guard.set_setting("game_mode", GameSettings.GameMode.VERSUS)
	var seat_a := Player.new(0, "A")
	var seat_b := Player.new(1, "B")
	PlayerManager.players.assign([seat_a, seat_b] as Array[Player])
	PlayerManager.current_player_index = 0

	var vision := _arm_vision()
	vision.hide_cells(0, [Vector2i(4, 4)])              # player 0 cannot see the far corner
	vision.hide_cells(1, [Vector2i(0, 0), Vector2i(0, 1)])  # player 1 cannot see the near one
	await _mount_fog()

	assert_eq(_shrouded_cells(), [Vector2i(4, 4)] as Array[Vector2i],
		"player 0's turn: player 0's blind spot is shrouded")

	# The seat changes hands, exactly as the active turn system announces it.
	PlayerManager.current_player_index = 1
	_fog._on_turn_started(seat_b)

	assert_eq(_shrouded_cells(), [Vector2i(0, 0), Vector2i(0, 1)] as Array[Vector2i],
		"player 1 takes the controls and the whole board flips to THEIR vision -- neither "
		+ "human may keep the other's eyes")
	_assert_instances_match()


func test_a_replay_shows_no_fog_at_all() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	var vision := _arm_vision()
	vision.hide_cells(0, [Vector2i(2, 2)])
	vision.hide_unit(0, _foe)

	ReplayPlayback.begin_playback()
	await _mount_fog()

	assert_eq(_fog.get_child_count(), 0, "a spectator gets no shroud")
	assert_true(_foe.is_visible_in_tree(), "and every unit on the board is on screen")
	assert_eq(FogOfWarOverlay.local_perspective(), FogOfWarOverlay.SPECTATOR,
		"the viewer has no seat, so there is nobody to hide anything from")


# =============================================================================
# INTERACTION HONESTY
# =============================================================================

func test_a_hidden_enemy_cannot_be_hovered() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_arm_vision().hide_unit(0, _foe)
	await _mount_fog()

	var panel: UnitHoverPanel = _mount(UnitHoverPanel.new()) as UnitHoverPanel
	await get_tree().process_frame

	# The real cursor_moved payload: GRID coordinates as Vector3(col, 0, row).
	panel._on_cursor_moved(Vector3(FOE_CELL.x, 0, FOE_CELL.y))
	assert_false(panel.visible,
		"hovering a fogged cell shows nothing -- the card would otherwise x-ray the "
		+ "enemy's name, HP and statuses straight through the mist")

	panel._on_cursor_moved(Vector3(ALLY_CELL.x, 0, ALLY_CELL.y))
	assert_true(panel.visible, "a unit you CAN see still inspects normally")


func test_a_hidden_enemy_cannot_be_cursor_selected() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_arm_vision().hide_unit(0, _foe)
	await _mount_fog()

	var cursor: Node3D = CURSOR_SCENE.instantiate()
	_mount(cursor)
	await get_tree().process_frame

	cursor.tile_position = Vector3(FOE_CELL.x, 0, FOE_CELL.y)
	assert_null(cursor.hovered_unit,
		"the cursor reports empty ground over a fogged enemy")
	cursor._handle_selection()
	assert_null(cursor.get_selected_unit(),
		"clicking it selects nothing -- selection IS inspection in this game, so a "
		+ "read-only inspect of a unit you cannot see is refused")

	cursor.tile_position = Vector3(ALLY_CELL.x, 0, ALLY_CELL.y)
	cursor._handle_selection()
	assert_eq(cursor.get_selected_unit(), _ally,
		"and a unit you can see selects exactly as before")


func test_the_threat_overlay_excludes_a_hidden_enemy() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_arm_vision()
	await _mount_fog()

	var layout: Control = await _mount_hud()
	var panel: Node = layout.get_node_or_null(
		"MarginContainer/MainContainer/MiddleArea/RightSidebar/UnitActionsPanel")
	if panel == null:
		pending("UnitActionsPanel not present in the mounted layout; skipping")
		return

	var seen: Array = panel._compute_enemy_threat_cells(_foe)
	assert_gt(seen.size(), 0,
		"a VISIBLE enemy's danger zone is computed exactly as before")

	_vision.hide_unit(0, _foe)
	_vision.notify()

	var unseen: Array = panel._compute_enemy_threat_cells(_foe)
	assert_eq(unseen.size(), 0,
		"a hidden enemy lights nothing -- a danger zone drawn for a unit you cannot see "
		+ "is a free map of where it is standing")


func test_the_turn_queue_masks_a_hidden_enemy_chip() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_arm_vision().hide_unit(0, _foe)
	await _mount_fog()

	var layout: Control = await _mount_hud()
	var queue: TurnQueue = layout.turn_queue as TurnQueue
	if queue == null:
		pending("TurnQueue not present in the mounted layout; skipping")
		return

	queue._update_queue_display([_ally, _foe], null)
	await get_tree().process_frame

	assert_eq(queue.unit_portraits.size(), 2,
		"the hidden enemy KEEPS its slot -- the order of what is coming was never a secret")

	var foe_chip: Control = queue.unit_portraits[1]
	var name_label: Label = foe_chip.get_node_or_null("NameLabel") as Label
	var speed_label: Label = foe_chip.get_node_or_null("SpeedLabel") as Label
	assert_not_null(name_label, "the chip has its name label")
	assert_not_null(speed_label, "the chip has its speed label")
	if name_label != null:
		assert_eq(name_label.text, TurnQueue.FOG_MASK_NAME,
			"but its identity is a silhouette, not 'Blightcap'")
	if speed_label != null:
		assert_eq(speed_label.text, TurnQueue.FOG_MASK_SPEED,
			"and its speed -- which would let you deduce the unit -- is masked too")

	var portrait: TextureRect = foe_chip.get_node_or_null("Portrait") as TextureRect
	if portrait != null:
		assert_false(portrait.visible, "and no portrait is shown")

	var ally_name: Label = (queue.unit_portraits[0] as Control).get_node_or_null("NameLabel")
	if ally_name != null:
		assert_eq(ally_name.text, _ally.get_display_name(),
			"a unit you can see is named normally -- masking is not blanket")


func test_a_masked_chip_is_inert() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_arm_vision().hide_unit(0, _foe)
	await _mount_fog()

	var layout: Control = await _mount_hud()
	var queue: TurnQueue = layout.turn_queue as TurnQueue
	if queue == null:
		pending("TurnQueue not present; skipping")
		return

	# Lambdas capture BY VALUE, so the counter is an Array (tests/README idiom).
	var selected: Array = []
	var probe := func(unit, _pos = null) -> void: selected.append(unit)
	GameEvents.unit_selected.connect(probe)

	queue._on_portrait_clicked(_foe)
	assert_eq(selected.size(), 0,
		"clicking the mask opens nothing -- otherwise the leak the mask prevents is "
		+ "reachable by clicking the mask itself")

	queue._on_portrait_clicked(_ally)
	assert_eq(selected.size(), 1, "a visible unit's chip still selects")

	GameEvents.unit_selected.disconnect(probe)


# =============================================================================
# LOG / ANNOUNCER DISCRETION
# =============================================================================

func test_the_battle_log_keeps_its_discretion() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_arm_vision().hide_unit(0, _foe)
	await _mount_fog()

	var layout: Control = await _mount_hud()
	var log_panel: BattleLog = layout.battle_log
	if log_panel == null:
		pending("BattleLog not present in the mounted layout; skipping")
		return

	# 1. A move by someone you cannot see is not reported at all.
	GameEvents.unit_moved.emit(_foe, Vector3.ZERO, Vector3(8.0, 0.0, 8.0))
	assert_false(log_panel._log.text.contains("Blightcap"),
		"an unseen unit is never named")
	assert_false(log_panel._log.text.contains("moved"),
		"and a move line is a POSITION -- there is no masked wording that survives, so "
		+ "the line is suppressed outright")

	# 2. A hit ON one of yours still lands, with the attacker masked.
	GameEvents.damage_dealt.emit(_foe, _ally, 12)
	assert_true(log_panel._log.text.contains("???"),
		"you can see your own soldier bleed: the hit is reported with the attacker masked")
	assert_true(log_panel._log.text.contains("Vineweave"),
		"and your unit is named, because you can see it")
	assert_false(log_panel._log.text.contains("Blightcap"),
		"the attacker's identity is still not given away")


func test_the_announcer_stays_quiet_for_an_unseen_caster() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_arm_vision().hide_unit(0, _foe)
	await _mount_fog()

	var layout: Control = await _mount_hud()
	var announcer: ActionAnnouncer = layout.action_announcer
	if announcer == null:
		pending("ActionAnnouncer not present in the mounted layout; skipping")
		return

	var move := MoveResource.new()
	move.move_id = &"test_fog_move"
	move.display_name = "Spore Volley"
	announcer._on_move_performed(_foe, move)

	assert_eq(announcer._queue.size(), 0,
		"no 40px banner across the top naming a unit standing in the mist")
	assert_false(announcer._busy, "nothing is being shown")

	announcer._on_move_performed(_ally, move)
	assert_true(announcer._queue.size() > 0 or announcer._busy,
		"a caster you CAN see is announced exactly as before")


func test_the_fog_intro_line_is_announced_once() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_arm_vision()
	await _mount_fog()
	var layout: Control = await _mount_hud()
	var announcer: ActionAnnouncer = layout.action_announcer
	if announcer == null:
		pending("ActionAnnouncer not present; skipping")
		return
	announcer._queue.clear()

	_fog.announce_fog_intro()
	var after_first: int = announcer._queue.size() + (1 if announcer._busy else 0)
	assert_gt(after_first, 0, "fog on: the player is told the rule before their first "
		+ "blind move")

	announcer._queue.clear()
	_fog.announce_fog_intro()
	assert_eq(announcer._queue.size(), 0,
		"ONCE per battle -- the courtesy line is not a per-turn nag")


# =============================================================================
# FX AND FLOATS
# =============================================================================

func test_damage_floats_are_suppressed_on_a_hidden_cell() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_arm_vision().hide_cells(0, [FOE_CELL])
	await _mount_fog()

	var numbers: Node3D = _mount(DAMAGE_NUMBERS.new()) as Node3D
	await get_tree().process_frame

	numbers._spawn_popup(_cell_to_world(FOE_CELL), "-12", Color.RED, 1.0)
	assert_eq(numbers.get_child_count(), 0,
		"a '-12' rising out of the mist is a perfect marker for the unit you are not "
		+ "supposed to know is there")

	numbers._spawn_popup(_cell_to_world(ALLY_CELL), "-12", Color.RED, 1.0)
	assert_eq(numbers.get_child_count(), 1,
		"and a hit you can see floats its number exactly as before")


func test_move_fx_erupts_only_on_the_cells_you_can_see() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_arm_vision().hide_cells(0, [Vector2i(3, 3), Vector2i(3, 4)])
	await _mount_fog()

	var fx: Node3D = _mount(MOVE_FX.new()) as Node3D
	await get_tree().process_frame

	var spec: Dictionary = fx._default_spec(Color.ORANGE)
	for cell in [Vector2i(2, 3), Vector2i(3, 3), Vector2i(3, 4)]:
		fx._spawn_impact(cell, spec)

	var lit: Array[Vector2i] = fx.live_impact_cells()
	assert_true(lit.has(Vector2i(2, 3)), "the cell in the open erupts")
	assert_false(lit.has(Vector2i(3, 3)),
		"a blast reaching into the mist is CLIPPED per cell -- the genre answer to a hit "
		+ "in fog is that you see nothing")
	assert_false(lit.has(Vector2i(3, 4)), "every fogged cell of the area, not just one")

	fx.clear_effects()


# =============================================================================
# REVEAL ON ATTACK -- the gates read visibility LIVE
# =============================================================================

func test_a_reveal_on_attack_is_rendered_not_suppressed() -> void:
	## The vision core reveals a hidden attacker BEFORE the damage announcement fires. Every
	## gate in this layer therefore has to read visibility at EVENT time; a suppression set
	## snapshotted at the last repaint would swallow the very attack that revealed the
	## attacker. This drives exactly that ordering -- the oracle flips, and only THEN does
	## the announcement arrive, with no vision_changed repaint in between.
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	var vision := _arm_vision()
	vision.hide_unit(0, _foe)
	vision.hide_cells(0, [FOE_CELL])
	await _mount_fog()

	var layout: Control = await _mount_hud()
	var log_panel: BattleLog = layout.battle_log
	if log_panel == null:
		pending("BattleLog not present; skipping")
		return
	var numbers: Node3D = _mount(DAMAGE_NUMBERS.new()) as Node3D
	await get_tree().process_frame

	assert_true(FogOfWarOverlay.unit_hidden(_foe), "before the attack it is unseen")

	# THE REVEAL LANDS FIRST -- and deliberately WITHOUT a repaint, so the only thing that
	# can save the announcement is a live read.
	vision.show_unit(0, _foe)
	vision.show_cells(0, [FOE_CELL])

	assert_false(FogOfWarOverlay.unit_hidden(_foe),
		"the gate answers from the core, not from the last repaint's cached set")

	GameEvents.damage_dealt.emit(_foe, _ally, 9)
	numbers._spawn_popup(_cell_to_world(FOE_CELL), "-9", Color.RED, 1.0)

	assert_true(log_panel._log.text.contains("Blightcap"),
		"the attack that revealed the attacker NAMES it -- the reveal is in effect before "
		+ "the announcement, so nothing is swallowed")
	assert_eq(numbers.get_child_count(), 1,
		"and its cell draws its damage float, because that cell is now in vision")


# =============================================================================
# THE REAL VISION CORE
# =============================================================================
#
# Every test above runs on the stub, so a failure there is always a failure of the LOOK.
# These two run the same layer against the REAL [VisionSystem], with no override installed,
# and are the ones that catch an API drift between the two halves -- notably that
# VisionSystem.visible_cells returns a { Vector2i: true } DICTIONARY, not an Array.

## Mount the real core over the live board, fed a map with [param fog] authored on it.
func _mount_real_vision(fog: bool) -> VisionSystem:
	var map := MapResource.new()
	map.width = COLS
	map.height = ROWS
	map.fog_of_war = fog

	var vision := VisionSystem.new()
	vision.name = "VisionSystem"
	_mount(vision)
	vision.setup()
	vision.set_board(CombatServices.board())
	vision.set_map(map)
	return vision


func test_the_real_vision_core_drives_the_same_shroud() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	var vision := _mount_real_vision(true)
	# NO override: the overlay has to find the core on its own, exactly as it does in battle.
	FogOfWarOverlay.set_vision_override(null)
	await _mount_fog()

	assert_true(FogOfWarOverlay.fog_active(),
		"MapResource.fog_of_war on -> the presentation layer arms itself off the real core")

	var perspective: int = FogOfWarOverlay.local_perspective()
	var lit: Dictionary = vision.visible_cells(perspective)
	var shrouded: Array[Vector2i] = _shrouded_cells()
	for col in range(COLS):
		for row in range(ROWS):
			var cell := Vector2i(col, row)
			assert_eq(shrouded.has(cell), not lit.has(cell),
				"cell (%d,%d): the veil is the exact complement of the core's lit set"
					% [col, row])
	_assert_instances_match()


func test_the_real_core_with_fog_off_leaves_the_battle_untouched() -> void:
	if not await _build_board():
		pending("could not build the board; skipping")
		return
	_mount_real_vision(false)
	FogOfWarOverlay.set_vision_override(null)
	await _mount_fog()

	assert_false(FogOfWarOverlay.fog_active(),
		"a map that never asked for fog leaves the whole layer inert")
	assert_eq(_fog.get_child_count(), 0, "no shroud geometry is built at all")
	assert_false(UnitVisualManager.is_fog_hidden(_foe), "and no unit is hidden")
	assert_true(_foe.is_visible_in_tree(), "the enemy renders exactly as it always did")
