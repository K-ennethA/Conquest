extends Node

## FREE MOVEMENT check in a real rendered run ([HeroMover], the shipped "free" feel). Run the
## scene (not headless -- it needs a renderer and real frame pacing):
##   godot --path . --resolution 1280x720 res://dev_scripts/free_walk_shots.tscn
## Boots Oakvale, holds left, then up + left, then Shift + left (real Input actions), and saves a
## filmstrip to user://free_walk_shots/ plus a per-frame log of the hero's ground speed: every
## frame of a held key should move him (no walking in place, no cell-sized jumps).

const OUT := "user://free_walk_shots/"
const OVERWORLD_SCENE := "res://game/overworld/OverworldScene.tscn"
const START := Vector3i(10, 11, 0)

var _ow: OverworldController = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	StoryController.scene_changes_enabled = false
	StoryController.end_session()
	StoryController.new_journey(0)
	var s: StoryState = StoryController.state()
	s.set_flag("opening.sent_off", 1)
	s.grace_steps = 9999
	s.on_area_changed()
	s.set_location("oakvale", START, "south")
	_ow = (load(OVERWORLD_SCENE) as PackedScene).instantiate() as OverworldController
	add_child(_ow)
	await _frames(30)
	print("[free_walk] feel: ", OverworldFeel.describe(_ow.feel))
	await _leg("west", [InputActions.CURSOR_LEFT], 1.4, 4)
	await _leg("northwest", [InputActions.CURSOR_LEFT, InputActions.CURSOR_UP], 1.0, 3)
	await _leg("run_east", [InputActions.CURSOR_RIGHT, InputActions.FAST_FORWARD], 0.9, 3)
	print("[free_walk] shots in ", ProjectSettings.globalize_path(OUT))
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	get_tree().quit()


## Hold [param actions] for [param seconds], saving [param shots] evenly spaced frames and
## logging the ground speed of every frame; then release and let him settle.
func _leg(label: String, actions: Array, seconds: float, shots: int) -> void:
	for a in actions:
		Input.action_press(a)
	var t: float = 0.0
	var next_shot: float = seconds / float(shots)
	var shot: int = 0
	var prev: Vector3 = _ow.player.global_position
	var stalls: int = 0
	var frames: int = 0
	var speeds: PackedFloat32Array = PackedFloat32Array()
	# process_frame fires BEFORE this frame's _process: the position read here is the one the
	# previous frame produced, over the previous frame's delta.
	var prev_dt: float = 0.0
	var shot_frame: bool = false
	while t < seconds:
		await get_tree().process_frame
		var p: Vector3 = _ow.player.global_position
		var v: float = Vector2(p.x - prev.x, p.z - prev.z).length() / prev_dt if prev_dt > 0.0 else 0.0
		prev = p
		frames += 1
		if t > 0.3 and not shot_frame:
			speeds.append(v)
			if v < 0.05:
				stalls += 1
		shot_frame = false
		prev_dt = get_process_delta_time()
		t += prev_dt
		if t >= next_shot * float(shot + 1) and shot < shots:
			_save("%s_%d.png" % [label, shot])
			shot += 1
			shot_frame = true
	for a in actions:
		Input.action_release(a)
	await _frames(20)
	var lo: float = INF
	var hi: float = 0.0
	for v in speeds:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	print("[free_walk] %s: %d frames, cruise speed %.2f..%.2f m/s, %d stalled frames, cell %s facing %s" % [
		label, frames, lo, hi, stalls, _ow.player.cell, _ow.player.facing])


func _save(file: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + file))


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
