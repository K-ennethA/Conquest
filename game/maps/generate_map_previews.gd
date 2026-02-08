@tool
extends EditorScript

# Run this script in the Godot editor to generate preview images for all maps
# File → Run → Select this script

func _run() -> void:
	print("=== Generating Map Previews ===")
	
	# Get all map files
	var map_files = MapLoader.get_available_maps()
	print("Found " + str(map_files.size()) + " maps")
	
	var generated_count = 0
	var failed_count = 0
	
	for map_path in map_files:
		print("\nProcessing: " + map_path)
		
		# Load map resource
		var map_resource = load(map_path) as MapResource
		if not map_resource:
			print("  ERROR: Failed to load map resource")
			failed_count += 1
			continue
		
		print("  Map: " + map_resource.map_name)
		print("  Size: " + str(map_resource.width) + "x" + str(map_resource.height))
		
		# Generate preview
		var preview_path = MapPreviewGenerator.generate_and_save_preview(map_resource)
		
		if not preview_path.is_empty():
			print("  Preview generated: " + preview_path)
			
			# Update map resource with preview path
			map_resource.preview_image_path = preview_path
			
			# Save updated map resource
			var save_result = ResourceSaver.save(map_resource, map_path)
			if save_result == OK:
				print("  Map resource updated with preview path")
				generated_count += 1
			else:
				print("  ERROR: Failed to save map resource: " + str(save_result))
				failed_count += 1
		else:
			print("  ERROR: Failed to generate preview")
			failed_count += 1
	
	print("\n=== Preview Generation Complete ===")
	print("Generated: " + str(generated_count))
	print("Failed: " + str(failed_count))
	print("Total: " + str(map_files.size()))
