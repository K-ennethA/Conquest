extends RefCounted

class_name TileTextureImporter

## Helper for turning an image file into a tile texture and wiring it onto a
## reusable [TileResource].
##
## It loads the image (from a res:// resource path or any OS/user:// file path),
## converts it into an [ImageTexture], saves that texture into a resources folder,
## and creates or updates a [TileResource] whose [member TileResource.texture_path]
## references it. Every entry point is defensive about missing / unreadable files
## and returns null / false rather than raising.

## Default directory where imported textures are saved.
const DEFAULT_TEXTURE_DIR := "res://game/mapmaker/imported"


## Loads [param image_path] and returns a [Texture2D], or null if it cannot be read.
## Accepts res:// resource paths as well as absolute OS paths and user:// paths.
static func load_texture(image_path: String) -> Texture2D:
	if image_path.is_empty():
		return null

	# Prefer the resource pipeline for res:// paths (handles already-imported assets).
	if image_path.begins_with("res://"):
		if ResourceLoader.exists(image_path):
			var resource := load(image_path)
			if resource is Texture2D:
				return resource
			if resource is Image:
				return ImageTexture.create_from_image(resource)

	# Fall back to loading the raw image bytes from disk.
	if not FileAccess.file_exists(image_path):
		return null
	var image := Image.new()
	var err := image.load(image_path)
	if err != OK or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## Saves [param texture] as a .res resource under [param save_dir] using
## [param base_name] for the file name. Returns the saved resource path, or an
## empty string on failure.
static func save_texture(texture: Texture2D, base_name: String, save_dir: String = DEFAULT_TEXTURE_DIR) -> String:
	if texture == null:
		return ""
	if not DirAccess.dir_exists_absolute(save_dir):
		var mk := DirAccess.make_dir_recursive_absolute(save_dir)
		if mk != OK:
			return ""
	var file_name := _slugify(base_name)
	if file_name.is_empty():
		file_name = "tile_texture"
	var texture_path := save_dir.path_join(file_name + "_tex.res")
	if ResourceSaver.save(texture, texture_path) != OK:
		return ""
	return texture_path


## Imports [param image_path] and returns a new [TileResource] that references the
## imported texture. Returns null if the image is missing or unreadable.
static func import_texture_as_tile(image_path: String, tile_name: String = "", save_dir: String = DEFAULT_TEXTURE_DIR) -> TileResource:
	var texture := load_texture(image_path)
	if texture == null:
		return null

	var resolved_name := tile_name
	if resolved_name.is_empty():
		resolved_name = image_path.get_file().get_basename()

	var texture_path := save_texture(texture, resolved_name, save_dir)
	if texture_path.is_empty():
		return null

	var tile := TileResource.new()
	tile.tile_name = resolved_name
	tile.texture_path = texture_path
	return tile


## Updates an existing [TileResource] so its texture references the imported
## [param image_path]. Returns true on success, false if the tile is null or the
## image cannot be loaded.
static func update_tile_texture(tile: TileResource, image_path: String, save_dir: String = DEFAULT_TEXTURE_DIR) -> bool:
	if tile == null:
		return false
	var texture := load_texture(image_path)
	if texture == null:
		return false
	var base_name := tile.tile_name if not tile.tile_name.is_empty() else image_path.get_file().get_basename()
	var texture_path := save_texture(texture, base_name, save_dir)
	if texture_path.is_empty():
		return false
	tile.texture_path = texture_path
	return true


## Imports a texture, wires it onto a [TileResource], and saves that tile as a
## .tres under [param save_dir]. Returns the saved tile path, or an empty string
## on failure.
static func import_and_save_tile(image_path: String, tile_name: String = "", save_dir: String = DEFAULT_TEXTURE_DIR) -> String:
	var tile := import_texture_as_tile(image_path, tile_name, save_dir)
	if tile == null:
		return ""
	var file_name := _slugify(tile.tile_name)
	if file_name.is_empty():
		file_name = "imported_tile"
	var tile_path := save_dir.path_join(file_name + ".tres")
	if ResourceSaver.save(tile, tile_path) != OK:
		return ""
	return tile_path


static func _slugify(text: String) -> String:
	var out := text.strip_edges().to_lower()
	var result := ""
	for i in out.length():
		var c := out[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			result += c
		elif c == " " or c == "-" or c == "_":
			result += "_"
	return result.strip_edges()
