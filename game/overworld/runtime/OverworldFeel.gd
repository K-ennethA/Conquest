extends CanvasLayer
class_name OverworldFeel

## OVERWORLD FEEL PRESETS (walk pace, glide, turns, camera) + the DEBUG-ONLY F8 A/B cycler.
## Artist directive, review-log 2026-10-04: "the walking and camera doesnt seem to match pokemon
## sun and moon style". Same pattern as [WorldLookPresetCycler] (F7): press F8 in an overworld
## launch to cycle [constant PRESET_ORDER] on the live [OverworldController]; a small corner
## label names the active preset and its numbers. Gameplay never changes between presets: the
## same cells are entered and the same arrivals fire -- only traversal timing, interpolation
## and the camera's presentation differ.
##
## "current"       -- the pre-2026-10-04 feel, verbatim: StoryRuleset walk / run_step_seconds
##                    (0.22 / 0.12 s per 2 m cell = 9.1 / 16.7 m/s -- the walk clip slid ~12x
##                    over the ground), a Tween per cell (a frame of idle at every cell centre),
##                    0.08 s linear turns, the battle camera's 50 deg pitch / 50 deg FOV at 14 m.
## "sunmoon"       -- Sun/Moon read: STRIDE-MATCHED pace (ground speed = the hero clip's stride /
##                    cycle x its playback rate, so the planted foot never slides), a continuous
##                    glide that carries each frame's leftover time into the next chained cell
##                    (no per-cell hitch), snappy ease-out turns, a lower / narrower / closer
##                    fixed-yaw camera with frame-rate-independent positional lag + look-ahead.
## "sunmoon-brisk" -- "sunmoon" with the walk clip played 2.0x instead of 1.5x: the one judgment
##                    axis the clip cannot settle (pace vs a credible walking cadence, see below).
##
## SOURCES / ASSUMPTIONS (cite, don't re-derive). Sun/Moon moves the trainer on the Circle Pad
## only (the D-pad is the Poke Ride shortcut), B held runs, and no camera control exists in the
## field (gamerguides.com Sun & Moon controls page) -> continuous movement, fixed camera yaw.
## The camera "pans and zooms based on where the player is standing" and goes behind the back
## in some areas (GameFAQs "Is the camera still fixed?" thread) -> a follow camera, no player
## rotation. No published numbers exist for Sun/Moon speeds or camera angles; the only measured
## Pokemon pace found is Gen 4 (Pearl): walk just under 4 tiles/s, run just under 8 (GameFAQs
## Pearl Q&A) -> run ~2x walk. ASSUMED here (each a knob below): pitch 38 deg / FOV 36 deg /
## 12.5 m puts the 1.75 m hero at ~17 % of the frame height (current: ~9 %), the Sun/Moon
## trainer reads at roughly a fifth of the 3DS top screen. PACE is bounded by the shipped walk
## clip, not by the reference: its stride is 0.833 m (0.48 body heights) at 110.8 steps/min, so
## a stride-matched walk is 0.77 m/s at 1.0x; 1.5x (166 steps/min) is the brisk end of a
## credible walk, 2.0x (222 steps/min) already scurries. A Sun/Moon-paced walk at a natural
## cadence needs a longer-stride walk clip from forge (~1.2 m), not a faster playback.
##
## Phone-viable: every number is resolved once per apply (a Dictionary built at boot / on F8),
## never per frame; the glide and the camera are plain _process maths on value types.

const NODE_NAME := "OverworldFeelCycler"
const GROUP := &"overworld_feel"
const ACTION := &"debug_cycle_feel"
const KEY := KEY_F8

const PRESET_CURRENT := "current"
const PRESET_SUNMOON := "sunmoon"
const PRESET_BRISK := "sunmoon-brisk"
const PRESET_ORDER: Array[String] = [PRESET_CURRENT, PRESET_SUNMOON, PRESET_BRISK]
const PRESET_DEFAULT := PRESET_SUNMOON

## pace "ruleset_step": walk / run seconds per cell straight from StoryRuleset (the legacy grid
## pace); pace "stride": speed = StoryRuleset hero stride / cycle x walk|run_clip_rate, and the
## seconds per cell follow from the speed (Cells.CELL_SIZE / speed) -- never the reverse.
## glide "tween" = a Tween per cell; "continuous" = the carry-over integrator
## ([member OverworldActor.continuous_glide]). cam_follow "lerp" = the legacy clamp(delta x rate)
## lerp; "smooth" = 1 - exp(-rate x delta) lag + a velocity look-ahead (seconds of travel, capped
## in metres, eased in at cam_lookahead_rate). Interiors keep the whole-room framing their
## camera bounds are derived from (OverworldController.camera_bounds_for: a 20 x 14 m view).
const PRESETS := {
	"current": {
		"pace": "ruleset_step", "walk_clip_rate": 1.0, "run_clip_rate": 1.0,
		"glide": "tween", "turn_time": 0.08, "turn_ease_out": false,
		"cam_pitch_deg": 50.0, "cam_fov_deg": 50.0, "cam_distance": 14.0,
		"cam_follow": "lerp", "cam_follow_rate": 7.0,
		"cam_lookahead_s": 0.0, "cam_lookahead_max": 0.0, "cam_lookahead_rate": 0.0,
		"interior_pitch_deg": 50.0, "interior_fov_deg": 50.0, "interior_distance": 13.5,
	},
	"sunmoon": {
		"pace": "stride", "walk_clip_rate": 1.5, "run_clip_rate": 1.0,
		"glide": "continuous", "turn_time": 0.1, "turn_ease_out": true,
		"cam_pitch_deg": 38.0, "cam_fov_deg": 36.0, "cam_distance": 12.5,
		"cam_follow": "smooth", "cam_follow_rate": 4.0,
		"cam_lookahead_s": 0.35, "cam_lookahead_max": 1.5, "cam_lookahead_rate": 2.5,
		"interior_pitch_deg": 50.0, "interior_fov_deg": 50.0, "interior_distance": 13.5,
	},
	"sunmoon-brisk": {
		"pace": "stride", "walk_clip_rate": 2.0, "run_clip_rate": 1.0,
		"glide": "continuous", "turn_time": 0.1, "turn_ease_out": true,
		"cam_pitch_deg": 38.0, "cam_fov_deg": 36.0, "cam_distance": 12.5,
		"cam_follow": "smooth", "cam_follow_rate": 4.0,
		"cam_lookahead_s": 0.35, "cam_lookahead_max": 1.5, "cam_lookahead_rate": 2.5,
		"interior_pitch_deg": 50.0, "interior_fov_deg": 50.0, "interior_distance": 13.5,
	},
}

## The preset every overworld boot applies (survives area warps; F8 changes it).
static var _active: String = PRESET_DEFAULT
static var _instance: OverworldFeel = null

var _label: Label = null


static func active() -> String:
	return _active


## Make [param preset] the one the next boot / [method OverworldController.apply_feel] uses.
static func set_active(preset: String) -> void:
	if PRESETS.has(preset):
		_active = preset


## [param preset] resolved against [param ruleset]: the preset's knobs plus the derived pace
## (walk / run speed in m/s and seconds per cell). Built once per apply, never per frame.
static func resolve(preset: String, ruleset: StoryRuleset) -> Dictionary:
	var name: String = preset if PRESETS.has(preset) else PRESET_DEFAULT
	var d: Dictionary = (PRESETS[name] as Dictionary).duplicate()
	d["name"] = name
	var cs: float = Cells.CELL_SIZE
	if String(d["pace"]) == "stride" and ruleset != null:
		var walk_v: float = ruleset.hero_walk_stride_m / ruleset.hero_walk_cycle_seconds * float(d["walk_clip_rate"])
		var run_v: float = ruleset.hero_run_stride_m / ruleset.hero_run_cycle_seconds * float(d["run_clip_rate"])
		d["walk_speed_mps"] = walk_v
		d["run_speed_mps"] = run_v
		d["walk_step_seconds"] = cs / walk_v
		d["run_step_seconds"] = cs / run_v
	else:
		var ws: float = ruleset.walk_step_seconds if ruleset != null else 0.22
		var rs: float = ruleset.run_step_seconds if ruleset != null else 0.12
		d["walk_step_seconds"] = ws
		d["run_step_seconds"] = rs
		d["walk_speed_mps"] = cs / ws
		d["run_speed_mps"] = cs / rs
	return d


## One line of numbers for logs / the A/B label.
static func describe(d: Dictionary) -> String:
	return "%s: walk %.3f m/s (%.3f s/cell, clip x%.2f), run %.3f m/s (%.3f s/cell, clip x%.2f), %s glide, turn %.2f s%s, cam pitch %.0f fov %.0f dist %.1f %s rate %.1f lead %.2f s<=%.1f m" % [
		d["name"], d["walk_speed_mps"], d["walk_step_seconds"], d["walk_clip_rate"],
		d["run_speed_mps"], d["run_step_seconds"], d["run_clip_rate"], d["glide"],
		d["turn_time"], " ease-out" if bool(d["turn_ease_out"]) else "",
		d["cam_pitch_deg"], d["cam_fov_deg"], d["cam_distance"], d["cam_follow"],
		d["cam_follow_rate"], d["cam_lookahead_s"], d["cam_lookahead_max"]]


# --- the debug cycler --------------------------------------------------------------------

static func enabled() -> bool:
	return OS.is_debug_build() and DisplayServer.get_name() != "headless"


## Ensure the single cycler exists (debug builds with a display only -- release exports and
## headless test runs never create it). The action is registered at runtime, so the project's
## [input] map and its rebinding UI stay untouched; F8 is bound by nothing in game/ (only stray
## dev_scripts/ test scenes read it).
static func attach(host: Node) -> void:
	if not enabled() or host == null or not host.is_inside_tree():
		return
	if _instance == null or not is_instance_valid(_instance):
		_instance = OverworldFeel.new()
		_instance.name = NODE_NAME
		host.get_tree().root.add_child.call_deferred(_instance)
	elif _instance.is_inside_tree():
		_instance._refresh_label()


func _init() -> void:
	layer = 128


func _ready() -> void:
	ensure_action()
	_label = Label.new()
	_label.name = "FeelLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 3)
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 8)
	# One line above the F7 look label (same corner, same style).
	_label.offset_top -= 18.0
	_label.offset_bottom -= 18.0
	add_child(_label)
	_refresh_label()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


static func ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var e := InputEventKey.new()
	e.keycode = KEY
	InputMap.action_add_event(ACTION, e)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.is_echo():
		return
	ensure_action()
	if event.is_action_pressed(ACTION):
		cycle()
		get_viewport().set_input_as_handled()


## Step to the next preset and apply it to every live overworld.
func cycle() -> void:
	var i: int = PRESET_ORDER.find(_active)
	_active = PRESET_ORDER[(i + 1) % PRESET_ORDER.size()]
	var tree := get_tree()
	if tree != null:
		for n in tree.get_nodes_in_group(GROUP):
			if n.has_method(&"apply_feel"):
				var d: Dictionary = n.apply_feel(_active)
				print("[OverworldFeel A/B] ", describe(d))
	_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	var d: Dictionary = resolve(_active, _ruleset_or_null())
	_label.text = "Feel [F8] %d/%d: %s  (walk %.2f m/s, run %.2f m/s, cam %.0f/%.0f deg %.1f m)" % [
		PRESET_ORDER.find(_active) + 1, PRESET_ORDER.size(), _active, d["walk_speed_mps"],
		d["run_speed_mps"], d["cam_pitch_deg"], d["cam_fov_deg"], d["cam_distance"]]


func _ruleset_or_null() -> StoryRuleset:
	var story := get_node_or_null("/root/StoryController")
	if story != null and story.has_method(&"ruleset"):
		return story.ruleset()
	return null
