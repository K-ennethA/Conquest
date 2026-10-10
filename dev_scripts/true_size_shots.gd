extends Node
## TRUE-SIZE check (CONQUEST.md "Size"): real Units at their design heights on a
## 2 m checker board, seen from the battle camera's 50 deg pitch, so the tile plates,
## overhang and head-height health bars can be judged at a glance.
##
## Run the scene (not headless -- it needs a renderer):
##   godot --path . --resolution 1800x1000 res://dev_scripts/true_size_shots.tscn [-- out.png]
##
## Front row = your side (blue plates), back row = the enemy (red plates). Barkling and
## Petalfang stand shoulder to shoulder on purpose: that is the worst overhang case.

const ROSTER := "res://game/characters/roster/"
const CELL := 2.0
const ALLIES := ["blightcap", "tree_grunt", "petalfang", "lyra", "wren", "magmoo", "firesprite"]
const ENEMIES := ["vineweave", "necromancer", "eldroot", "varden", "vampwarrior"]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "res://docs/screenshots/true_size/board.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	await get_tree().process_frame

	var world := Node3D.new()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.9
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.shadow_enabled = true
	world.add_child(sun)

	# 9 x 6 checker board of 2 m tiles, cell (c, r) centred at (c*2, 0, r*2).
	for c in range(9):
		for r in range(6):
			var t := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(CELL, 0.2, CELL)
			t.mesh = box
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.36, 0.46, 0.3) if (c + r) % 2 == 0 else Color(0.31, 0.4, 0.26)
			t.material_override = m
			t.position = Vector3(c * CELL, -0.1, r * CELL)
			world.add_child(t)

	var vm := UnitVisualManager.new()
	vm.name = "UnitVisualManager"
	world.add_child(vm)
	var me := Player.new(0, "You")
	var foe := Player.new(1, "Foe")
	foe.is_ai = true

	for i in ALLIES.size():
		_spawn(world, vm, ALLIES[i], Vector3i(1 + i, 0, 4), me)
	var col := 1
	for id in ENEMIES:
		_spawn(world, vm, id, Vector3i(col, 0, 1), foe)
		col += 3 if id == "eldroot" else 1

	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.position = Vector3(8.0, 12.5, 15.0)
	cam.rotation_degrees = Vector3(-50.0, 0.0, 0.0)
	cam.current = true

	for i in 8:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))
	get_tree().quit()

func _spawn(world: Node3D, vm: UnitVisualManager, id: String, cell: Vector3i, owner: Player) -> void:
	var u := Unit.new()
	u.name = id
	u.character_resource = load(ROSTER + id + ".tres")
	u.stats_resource = UnitStatsResource.new()
	u.position = Vector3(cell.x * CELL, 0.0, cell.z * CELL)
	u.owner_player = owner
	world.add_child(u)
	vm.setup_unit_visuals(u, PlayerMaterials.PlayerTeam.PLAYER_1)
	# The battle plays each model's authored idle (UnitAnimator); a bare scene would
	# show the REST pose instead, which for some rigs (Magmoo) is not how they stand.
	for ap in u.find_children("*", "AnimationPlayer", true, false):
		for clip in (ap as AnimationPlayer).get_animation_list():
			if String(clip).to_lower().get_slice("|", String(clip).get_slice_count("|") - 1) == "idle":
				(ap as AnimationPlayer).play(clip)
				break
