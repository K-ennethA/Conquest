extends GutTest

## Unit tests for TileTextureImporter.
## Covers robust handling of missing files plus successful import of a generated
## image into a TileResource that references the imported texture.

const TEST_IMAGE_PATH := "user://test_mapmaker_tile.png"
const TEST_SAVE_DIR := "user://test_mapmaker_imported"


func before_each():
	_write_test_image()


func after_each():
	# Clean up generated artifacts.
	if FileAccess.file_exists(TEST_IMAGE_PATH):
		DirAccess.remove_absolute(TEST_IMAGE_PATH)
	_remove_dir_recursive(TEST_SAVE_DIR)


func _write_test_image():
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.6, 0.9, 1.0))
	image.save_png(TEST_IMAGE_PATH)


func _remove_dir_recursive(path: String):
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute(path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


# --- Robustness --------------------------------------------------------------
func test_load_missing_file_returns_null():
	var tex := TileTextureImporter.load_texture("user://no_such_image_xyz.png")
	assert_null(tex, "Loading a missing image returns null, not a crash")


func test_import_missing_file_returns_null():
	var tile := TileTextureImporter.import_texture_as_tile("user://no_such_image_xyz.png", "Missing", TEST_SAVE_DIR)
	assert_null(tile, "Importing a missing image returns null")


func test_import_empty_path_returns_null():
	var tile := TileTextureImporter.import_texture_as_tile("", "Empty", TEST_SAVE_DIR)
	assert_null(tile, "Importing an empty path returns null")


func test_update_tile_texture_null_tile_returns_false():
	var ok := TileTextureImporter.update_tile_texture(null, TEST_IMAGE_PATH, TEST_SAVE_DIR)
	assert_false(ok, "Updating a null tile returns false")


# --- Successful import -------------------------------------------------------
func test_load_valid_image_returns_texture():
	var tex := TileTextureImporter.load_texture(TEST_IMAGE_PATH)
	assert_not_null(tex, "Valid image loads to a Texture2D")
	assert_true(tex is Texture2D, "Result is a Texture2D")


func test_import_creates_tile_resource_with_texture():
	var tile := TileTextureImporter.import_texture_as_tile(TEST_IMAGE_PATH, "My Tile", TEST_SAVE_DIR)
	assert_not_null(tile, "Import produced a TileResource")
	assert_true(tile is TileResource, "Result is a TileResource")
	assert_eq(tile.tile_name, "My Tile", "Tile name applied")
	assert_false(tile.texture_path.is_empty(), "Texture path set on tile")
	assert_true(ResourceLoader.exists(tile.texture_path), "Imported texture saved and loadable")


func test_update_tile_texture_valid():
	var tile := TileResource.new()
	tile.tile_name = "Updatable"
	var ok := TileTextureImporter.update_tile_texture(tile, TEST_IMAGE_PATH, TEST_SAVE_DIR)
	assert_true(ok, "Update succeeds with valid image")
	assert_false(tile.texture_path.is_empty(), "Texture path set after update")


func test_import_and_save_tile_writes_tres():
	var path := TileTextureImporter.import_and_save_tile(TEST_IMAGE_PATH, "Saved Tile", TEST_SAVE_DIR)
	assert_false(path.is_empty(), "import_and_save_tile returns a path")
	assert_true(ResourceLoader.exists(path), "Saved tile .tres exists")
	var loaded := load(path) as TileResource
	assert_not_null(loaded, "Saved tile loads back as TileResource")
	assert_false(loaded.texture_path.is_empty(), "Loaded tile retains texture path")
