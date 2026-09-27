extends SceneTree
## Roster FACING check: renders every roster character (game/characters/roster) in a
## grid so a wrong model_yaw_deg is obvious at a glance. Columns = characters; rows =
## facings; a yellow tile marks the cell each model SHOULD be looking at. The camera
## looks from +Z (south) and above, like the battle camera.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --rendering-driver opengl3 \
##     --resolution 1800x1000 -s res://dev_scripts/render_unit_facing.gd -- out.png [mode]
##
## mode "facing" (default): rows South (toward camera), East (screen right), North,
##   West -- through UnitFacing.model_yaw, exactly what a Unit does in battle.
## mode "raw": row 1 = the .glb as exported (no yaw), row 2 = raw turned +90 deg
##   (a model whose face points +Z then looks screen-right) -- to find the
##   exporter's forward axis for a new model.

const ROSTER_DIR := "res://game/characters/roster"
const SPACING := 3.0
const ROW_SPACING := 3.6

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://unit_facing.png"
	var mode: String = args[1] if args.size() > 1 else "facing"
	# Optional 3rd arg: comma-separated roster file stems to render (bigger).
	var only: PackedStringArray = args[2].split(",", false) if args.size() > 2 else PackedStringArray()
	await process_frame

	var root3d := Node3D.new()
	root.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.9
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	root3d.add_child(sun)

	var chars: Array = []
	var files := DirAccess.get_files_at(ROSTER_DIR)
	files.sort()
	for f in files:
		if f.ends_with(".tres") and (only.is_empty() or f.get_basename() in only):
			var c = load(ROSTER_DIR + "/" + f)
			if c is CharacterResource and c.model_scene != null:
				chars.append(c)

	# [label, facing (Vector2i) or raw degrees (float), expected look direction]
	var rows: Array = []
	if mode == "raw":
		rows = [["raw", 0.0, Vector2i(0, 1)], ["raw+90", 90.0, Vector2i(1, 0)],
			["raw+180", 180.0, Vector2i(0, -1)]]
	else:
		rows = [["S", Vector2i(0, 1), Vector2i(0, 1)], ["E", Vector2i(1, 0), Vector2i(1, 0)],
			["N", Vector2i(0, -1), Vector2i(0, -1)], ["W", Vector2i(-1, 0), Vector2i(-1, 0)]]

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.28, 0.32, 0.3)
	var mark_mat := StandardMaterial3D.new()
	mark_mat.albedo_color = Color(1.0, 0.8, 0.2)
	mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for ci in chars.size():
		var chr: CharacterResource = chars[ci]
		var x := (ci - (chars.size() - 1) * 0.5) * SPACING
		for ri in rows.size():
			var z := -ri * ROW_SPACING
			var tile := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(1.9, 0.1, 1.9)
			tile.mesh = tm
			tile.material_override = floor_mat
			tile.position = Vector3(x, -0.05, z)
			root3d.add_child(tile)
			var m := chr.model_scene.instantiate() as Node3D
			root3d.add_child(m)
			m.position = Vector3(x, 0, z)
			var s := maxf(0.05, chr.model_scale)
			if chr.footprint.x > 1 or chr.footprint.y > 1:
				s *= 0.5  # keep a 2x2 boss inside its column
			m.scale = Vector3.ONE * s
			if rows[ri][1] is Vector2i:
				m.rotation.y = UnitFacing.model_yaw(chr.model_yaw_deg, rows[ri][1])
			else:
				m.rotation.y = deg_to_rad(float(rows[ri][1]))
			var dir: Vector2i = rows[ri][2]
			var marker := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 0.06, 0.5)
			marker.mesh = bm
			marker.material_override = mark_mat
			marker.position = Vector3(x + dir.x * 1.25, 0.03, z + dir.y * 1.25)
			root3d.add_child(marker)
		var lab := Label3D.new()
		lab.text = "%s\nyaw %d" % [chr.display_name.get_slice(",", 0), int(chr.model_yaw_deg)]
		lab.font_size = 40
		lab.outline_size = 8
		lab.position = Vector3(x, 0.2, 2.2)
		lab.rotation_degrees.x = -40
		root3d.add_child(lab)
	for ri in rows.size():
		var lab := Label3D.new()
		lab.text = String(rows[ri][0])
		lab.font_size = 64
		lab.outline_size = 10
		lab.position = Vector3(-(chars.size() + 0.6) * 0.5 * SPACING, 0.5, -ri * ROW_SPACING)
		lab.rotation_degrees.x = -40
		root3d.add_child(lab)

	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = (chars.size() + 0.9) * SPACING
	var mid_z := -(rows.size() - 1) * ROW_SPACING * 0.5
	var pitch: float = float(args[3]) if args.size() > 3 else 40.0  # camera tilt (deg)
	cam.position = Vector3(0, 30, mid_z + 30 / tan(deg_to_rad(pitch)))
	cam.look_at(Vector3(0, 0.6, mid_z))
	cam.current = true
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out, " (", chars.size(), " characters)")
	quit()
