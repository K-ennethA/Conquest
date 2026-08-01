extends GutTest

## Focused tests for MapMakerScene's terrain-passability enforcement -- the "can't place
## a unit on a wall/tree" creator logic checks. Covers both halves:
##   1. SPAWN / OBJECTIVE placement is REFUSED on impassable terrain.
##   2. Painting an impassable tile OVER an existing spawn/objective AUTO-REMOVES it
##      (the chosen "less annoying mid-sketch" behaviour vs. blocking the paint stroke).
##
## Exercises MapMakerScene directly WITHOUT calling _ready() / adding it to the scene
## tree -- no _build_ui(), no SubViewport, no 3D preview world. The methods under test
## only touch `model`, the (empty, never-built) `_cell_buttons` dict, and the (null,
## never-built) `_status_label`, all of which degrade safely when the scene was never
## built (see MapMakerScene._deny_placement / _flash_cell_denied / _set_status), so this
## stays headless-safe and fast.

const WALL_TILE_ID := "stone_wall"    # game/tiles/resources/common/stone_wall.tres
const GRASS_TILE_ID := "grass_plains" # game/tiles/resources/forest/grass_plains.tres

var scene: MapMakerScene
var model: MapMakerModel


func before_each():
	model = MapMakerModel.new(5, 5)
	scene = MapMakerScene.new()
	scene.model = model


func after_each():
	scene = null
	model = null


# --- Placement refusal (SPAWN / OBJECTIVE tools) ------------------------------

func test_toggle_spawn_denied_on_wall_tile():
	model.paint_tile(Vector2i(2, 2), "WALL", "", WALL_TILE_ID)
	scene._toggle_spawn_at(Vector2i(2, 2))
	assert_true(model.get_spawn(Vector2i(2, 2)).is_empty(), "spawn must not be placed on a wall tile")


func test_toggle_spawn_allowed_on_passable_tile():
	model.paint_tile(Vector2i(2, 2), "NORMAL", "", GRASS_TILE_ID)
	scene._toggle_spawn_at(Vector2i(2, 2))
	assert_false(model.get_spawn(Vector2i(2, 2)).is_empty(), "spawn should be placed on passable terrain")


func test_toggle_objective_denied_on_wall_tile():
	model.paint_tile(Vector2i(1, 1), "WALL", "", WALL_TILE_ID)
	scene._toggle_objective_at(Vector2i(1, 1))
	assert_true(model.get_objective(Vector2i(1, 1)).is_empty(), "objective must not be placed on a wall tile")


func test_toggle_objective_allowed_on_passable_tile():
	model.paint_tile(Vector2i(1, 1), "NORMAL", "", GRASS_TILE_ID)
	scene._toggle_objective_at(Vector2i(1, 1))
	assert_false(model.get_objective(Vector2i(1, 1)).is_empty(), "objective should be placed on passable terrain")


func test_removing_an_existing_spawn_ignores_terrain():
	# Toggling OFF an existing spawn must always work, even if terrain later became
	# impassable underneath it (e.g. via direct model edits bypassing the paint guard).
	model.paint_tile(Vector2i(2, 2), "NORMAL", "", GRASS_TILE_ID)
	model.place_spawn(Vector2i(2, 2), 0)
	model.paint_tile(Vector2i(2, 2), "WALL", "", WALL_TILE_ID)  # direct model edit, bypasses the scene guard
	scene._toggle_spawn_at(Vector2i(2, 2))  # should remove, not attempt to re-place
	assert_true(model.get_spawn(Vector2i(2, 2)).is_empty(), "toggling an existing spawn always removes it")


# --- Paint-over auto-remove ----------------------------------------------------

func test_painting_wall_over_spawn_removes_it():
	model.paint_tile(Vector2i(3, 3), "NORMAL", "", GRASS_TILE_ID)
	model.place_spawn(Vector2i(3, 3), 0)
	assert_false(model.get_spawn(Vector2i(3, 3)).is_empty(), "sanity: spawn placed before repaint")

	scene._selected_tile_type = "WALL"
	scene._selected_tile_path = ""
	scene._selected_tile_id = WALL_TILE_ID
	scene._paint_at(Vector2i(3, 3))

	assert_true(model.get_spawn(Vector2i(3, 3)).is_empty(), "painting a wall over a spawn auto-removes it")
	assert_eq(model.get_tile(Vector2i(3, 3))["tile_id"], WALL_TILE_ID, "the paint itself still applied")


func test_painting_wall_over_objective_removes_it():
	model.paint_tile(Vector2i(4, 0), "NORMAL", "", GRASS_TILE_ID)
	model.set_objective(Vector2i(4, 0), "THRONE", 0)

	scene._selected_tile_type = "WALL"
	scene._selected_tile_path = ""
	scene._selected_tile_id = WALL_TILE_ID
	scene._paint_at(Vector2i(4, 0))

	assert_true(model.get_objective(Vector2i(4, 0)).is_empty(), "painting a wall over an objective auto-removes it")


func test_painting_wall_over_empty_cell_is_a_no_op_beyond_the_paint():
	scene._selected_tile_type = "WALL"
	scene._selected_tile_path = ""
	scene._selected_tile_id = WALL_TILE_ID
	scene._paint_at(Vector2i(0, 0))
	assert_true(model.get_spawn(Vector2i(0, 0)).is_empty())
	assert_true(model.get_objective(Vector2i(0, 0)).is_empty())
	assert_eq(model.get_tile(Vector2i(0, 0))["tile_id"], WALL_TILE_ID, "the paint itself still applied")


func test_painting_passable_tile_over_spawn_keeps_it():
	model.paint_tile(Vector2i(3, 3), "NORMAL", "", GRASS_TILE_ID)
	model.place_spawn(Vector2i(3, 3), 0)

	scene._selected_tile_type = "NORMAL"
	scene._selected_tile_path = ""
	scene._selected_tile_id = GRASS_TILE_ID
	scene._paint_at(Vector2i(3, 3))

	assert_false(model.get_spawn(Vector2i(3, 3)).is_empty(), "repainting passable terrain must not disturb the spawn")
