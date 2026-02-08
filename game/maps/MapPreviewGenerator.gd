extends Node

class_name MapPreviewGenerator

# Generates preview images for maps
# Can create simple top-down visualizations of map layouts

static func generate_preview_for_map(map_resource: MapResource, size: Vector2i = Vector2i(400, 300)) -> Image:
	"""Generate a preview image for a map resource"""
	if not map_resource:
		return null
	
	var image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.2, 0.3, 1.0))  # Background color
	
	var map_size = map_resource.get_map_size()
	if map_size.x == 0 or map_size.y == 0:
		return image
	
	# Calculate tile size to fit the preview
	var padding = 20
	var available_width = size.x - (padding * 2)
	var available_height = size.y - (padding * 2)
	
	var tile_width = available_width / map_size.x
	var tile_height = available_height / map_size.y
	var tile_size = min(tile_width, tile_height)
	
	# Center the map in the preview
	var offset_x = (size.x - (tile_size * map_size.x)) / 2
	var offset_y = (size.y - (tile_size * map_size.y)) / 2
	
	# Draw tiles
	for x in range(map_size.x):
		for y in range(map_size.y):
			var tile_data = map_resource.get_tile_at_position(Vector2i(x, y))
			var tile_type = tile_data.get("tile_type", "NORMAL")
			
			var tile_color = _get_tile_color(tile_type)
			var tile_x = int(offset_x + (x * tile_size))
			var tile_y = int(offset_y + (y * tile_size))
			
			_draw_rect(image, tile_x, tile_y, int(tile_size), int(tile_size), tile_color)
			
			# Draw grid lines
			_draw_rect_outline(image, tile_x, tile_y, int(tile_size), int(tile_size), Color(0.1, 0.1, 0.1, 0.5))
	
	# Draw unit spawns
	for spawn_data in map_resource.unit_spawns:
		var pos = spawn_data.get("position", Vector2i(-1, -1))
		if pos == Vector2i(-1, -1):
			continue
		
		var player_id = spawn_data.get("player_id", 0)
		var unit_color = _get_player_color(player_id)
		
		var unit_x = int(offset_x + (pos.x * tile_size) + (tile_size / 4))
		var unit_y = int(offset_y + (pos.y * tile_size) + (tile_size / 4))
		var unit_size = int(tile_size / 2)
		
		_draw_circle(image, unit_x + unit_size / 2, unit_y + unit_size / 2, unit_size / 2, unit_color)
	
	return image

static func save_preview_image(image: Image, map_name: String) -> String:
	"""Save preview image to file and return path"""
	if not image:
		return ""
	
	# Ensure preview directory exists
	var preview_dir = "res://game/maps/previews/"
	if not DirAccess.dir_exists_absolute(preview_dir):
		DirAccess.open("res://").make_dir_recursive("game/maps/previews")
	
	# Clean filename
	var clean_name = map_name.to_lower().replace(" ", "_")
	var save_path = preview_dir + clean_name + ".png"
	
	# Save image
	var result = image.save_png(save_path)
	if result == OK:
		print("Preview saved: " + save_path)
		return save_path
	else:
		print("Failed to save preview: " + str(result))
		return ""

static func generate_and_save_preview(map_resource: MapResource) -> String:
	"""Generate and save preview for a map resource"""
	if not map_resource:
		return ""
	
	var image = generate_preview_for_map(map_resource)
	if not image:
		return ""
	
	var map_name = map_resource.map_name if not map_resource.map_name.is_empty() else "unnamed_map"
	return save_preview_image(image, map_name)

# Helper functions for drawing
static func _draw_rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	"""Draw a filled rectangle on the image"""
	for py in range(height):
		for px in range(width):
			var pixel_x = x + px
			var pixel_y = y + py
			if pixel_x >= 0 and pixel_x < image.get_width() and pixel_y >= 0 and pixel_y < image.get_height():
				image.set_pixel(pixel_x, pixel_y, color)

static func _draw_rect_outline(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	"""Draw a rectangle outline on the image"""
	# Top and bottom
	for px in range(width):
		var pixel_x = x + px
		if pixel_x >= 0 and pixel_x < image.get_width():
			if y >= 0 and y < image.get_height():
				image.set_pixel(pixel_x, y, color)
			if y + height - 1 >= 0 and y + height - 1 < image.get_height():
				image.set_pixel(pixel_x, y + height - 1, color)
	
	# Left and right
	for py in range(height):
		var pixel_y = y + py
		if pixel_y >= 0 and pixel_y < image.get_height():
			if x >= 0 and x < image.get_width():
				image.set_pixel(x, pixel_y, color)
			if x + width - 1 >= 0 and x + width - 1 < image.get_width():
				image.set_pixel(x + width - 1, pixel_y, color)

static func _draw_circle(image: Image, center_x: int, center_y: int, radius: int, color: Color) -> void:
	"""Draw a filled circle on the image"""
	for py in range(-radius, radius + 1):
		for px in range(-radius, radius + 1):
			if px * px + py * py <= radius * radius:
				var pixel_x = center_x + px
				var pixel_y = center_y + py
				if pixel_x >= 0 and pixel_x < image.get_width() and pixel_y >= 0 and pixel_y < image.get_height():
					image.set_pixel(pixel_x, pixel_y, color)

static func _get_tile_color(tile_type: String) -> Color:
	"""Get color for a tile type"""
	match tile_type.to_upper():
		"NORMAL":
			return Color(0.4, 0.6, 0.4, 1.0)  # Green
		"MOUNTAIN":
			return Color(0.5, 0.5, 0.5, 1.0)  # Gray
		"WATER":
			return Color(0.2, 0.4, 0.8, 1.0)  # Blue
		"FOREST":
			return Color(0.2, 0.5, 0.2, 1.0)  # Dark green
		"DESERT":
			return Color(0.8, 0.7, 0.4, 1.0)  # Sand
		"ROAD":
			return Color(0.6, 0.5, 0.4, 1.0)  # Brown
		_:
			return Color(0.4, 0.6, 0.4, 1.0)  # Default green

static func _get_player_color(player_id: int) -> Color:
	"""Get color for a player"""
	match player_id:
		0:
			return Color(0.8, 0.2, 0.2, 1.0)  # Red
		1:
			return Color(0.2, 0.2, 0.8, 1.0)  # Blue
		2:
			return Color(0.2, 0.8, 0.2, 1.0)  # Green
		3:
			return Color(0.8, 0.8, 0.2, 1.0)  # Yellow
		_:
			return Color(0.8, 0.8, 0.8, 1.0)  # White
