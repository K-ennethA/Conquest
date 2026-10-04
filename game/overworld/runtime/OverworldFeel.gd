extends CanvasLayer
class_name OverworldFeel

## OVERWORLD FEEL PRESETS (movement model, pace, turns, camera) + the DEBUG-ONLY F8 A/B cycler.
## Artist directives, review-log 2026-10-04: "the walking and camera doesnt seem to match pokemon
## sun and moon style", then "holding down the movement arrow key has the character pause and
## move in place then abruptly move spots ... we are stuck going tile by tile". Same pattern as
## [WorldLookPresetCycler] (F7): press F8 in an overworld launch to cycle [constant PRESET_ORDER]
## on the live [OverworldController]; a small corner label names the active preset.
##
## "free"        -- THE SHIPPED FEEL, Sun/Moon: FREE MOVEMENT ([HeroMover]). The hero walks at
##                  any angle (8-way keys, analog sticks), eases in / out, slides along walls and
##                  turns toward the input at any angle; the walk / run clips play at the rate his
##                  actual ground speed asks for (stride-matched: the planted foot holds). Never
##                  gated on the Animations setting -- moving is gameplay, not decoration. Cells
##                  still own the rules: entering a new cell fires its arrival.
## "free-brisk"  -- "free" a notch quicker (walk 2.3 / run 5.0 m/s).
## "grid"        -- the first Sun/Moon pass: one CELL per held step, stride-matched pace (walk
##                  clip 1.5x = 1.15 m/s, 1.7 s per 2 m cell), a continuous glide between chained
##                  cells. With Animations OFF each step snapped after its full step time: the
##                  hero walked in place, then jumped a cell -- the reported bug.
## "grid-legacy" -- the pre-2026-10-04 grid feel: StoryRuleset walk / run_step_seconds (0.22 /
##                  0.12 s per cell, the walk clip slid ~12x over the ground), a Tween per cell,
##                  the battle camera's 50 deg pitch / 50 deg FOV at 14 m.
##
## FREE PACE (knobs below, ASSUMED -- no published Sun/Moon numbers). Walk 1.8 m/s is about one
## body height per second for the 1.75 m hero (~1.1 s per 2 m cell); run 4.2 m/s is ~2.3x walk.
## The shipped walk clip strides only 0.833 m per cycle, so 1.8 m/s plays it at 2.34x (~260
## steps/min): a quick, short-legged cadence that suits the chibi Sun/Moon read. A longer-stride
## walk clip from forge (~1.2 m) would relax the cadence -- update StoryRuleset's
## hero_walk_stride_m / cycle and the playback rates follow.
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

const PRESET_FREE := "free"
const PRESET_FREE_BRISK := "free-brisk"
const PRESET_GRID := "grid"
const PRESET_GRID_LEGACY := "grid-legacy"
const PRESET_ORDER: Array[String] = [PRESET_FREE, PRESET_FREE_BRISK, PRESET_GRID, PRESET_GRID_LEGACY]
const PRESET_DEFAULT := PRESET_FREE
const MOVEMENT_FREE := "free"
const MOVEMENT_GRID := "grid"

## movement "free" = the hero walks freely ([HeroMover]); "grid" = one cell per held step.
## pace "speed": walk / run_speed_mps given, the clip rates derived (speed / the clip's own
## speed); pace "stride": speed = StoryRuleset hero stride / cycle x walk|run_clip_rate; pace
## "ruleset_step": StoryRuleset walk / run_step_seconds (the legacy grid pace). The seconds per
## cell always follow from the speed (Cells.CELL_SIZE / speed): scripted walks and NPCs use them.
## glide "tween" = a Tween per cell; "continuous" = the carry-over integrator
## ([member OverworldActor.continuous_glide]) -- cell walks (grid hero, scripts, NPCs).
## accel_rate / decel_rate / free_turn_rate: [HeroMover]'s exponential rates; run_clip_above:
## the ground speed (x walk speed) above which the run clip replaces the walk clip.
## cam_follow "lerp" = the legacy clamp(delta x rate) lerp; "smooth" = 1 - exp(-rate x delta)
## lag + a velocity look-ahead (seconds of travel, capped in metres, eased in at
## cam_lookahead_rate). A preset without camera keys takes [constant SUNMOON_CAMERA]. Interiors
## keep the whole-room framing their camera bounds are derived from
## (OverworldController.camera_bounds_for: a 20 x 14 m view).
const SUNMOON_CAMERA := {
	"cam_pitch_deg": 38.0, "cam_fov_deg": 36.0, "cam_distance": 12.5,
	"cam_follow": "smooth", "cam_follow_rate": 4.0,
	"cam_lookahead_s": 0.35, "cam_lookahead_max": 1.5, "cam_lookahead_rate": 2.5,
	"interior_pitch_deg": 50.0, "interior_fov_deg": 50.0, "interior_distance": 13.5,
}
const PRESETS := {
	"free": {
		"movement": "free", "pace": "speed", "walk_speed_mps": 2.2, "run_speed_mps": 5.0,
		"accel_rate": 14.0, "decel_rate": 22.0, "free_turn_rate": 18.0, "run_clip_above": 1.25,
		"glide": "continuous", "turn_time": 0.1, "turn_ease_out": true,
	},
	"free-brisk": {
		"movement": "free", "pace": "speed", "walk_speed_mps": 2.6, "run_speed_mps": 5.6,
		"accel_rate": 16.0, "decel_rate": 24.0, "free_turn_rate": 20.0, "run_clip_above": 1.25,
		"glide": "continuous", "turn_time": 0.1, "turn_ease_out": true,
	},
	"grid": {
		"movement": "grid", "pace": "stride", "walk_clip_rate": 1.5, "run_clip_rate": 1.0,
		"glide": "continuous", "turn_time": 0.1, "turn_ease_out": true,
	},
	"grid-legacy": {
		"movement": "grid", "pace": "ruleset_step", "walk_clip_rate": 1.0, "run_clip_rate": 1.0,
		"glide": "tween", "turn_time": 0.08, "turn_ease_out": false,
		"cam_pitch_deg": 50.0, "cam_fov_deg": 50.0, "cam_distance": 14.0,
		"cam_follow": "lerp", "cam_follow_rate": 7.0,
		"cam_lookahead_s": 0.0, "cam_lookahead_max": 0.0, "cam_lookahead_rate": 0.0,
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
	var d: Dictionary = SUNMOON_CAMERA.duplicate()
	d.merge(PRESETS[name] as Dictionary, true)
	d["name"] = name
	var cs: float = Cells.CELL_SIZE
	# The hero clips' own ground speeds (stride / cycle at 1.0x; the shipped ruleset's numbers
	# when no ruleset is at hand).
	var walk_native: float = 0.8332 / 1.0833
	var run_native: float = 2.3992 / 0.5
	if ruleset != null and ruleset.hero_walk_cycle_seconds > 0.0 and ruleset.hero_run_cycle_seconds > 0.0:
		walk_native = ruleset.hero_walk_stride_m / ruleset.hero_walk_cycle_seconds
		run_native = ruleset.hero_run_stride_m / ruleset.hero_run_cycle_seconds
	d["walk_clip_native_mps"] = walk_native
	d["run_clip_native_mps"] = run_native
	match String(d["pace"]):
		"speed":
			d["walk_clip_rate"] = float(d["walk_speed_mps"]) / walk_native
			d["run_clip_rate"] = float(d["run_speed_mps"]) / run_native
		"stride":
			d["walk_speed_mps"] = walk_native * float(d["walk_clip_rate"])
			d["run_speed_mps"] = run_native * float(d["run_clip_rate"])
		_:
			var ws: float = ruleset.walk_step_seconds if ruleset != null else 0.22
			var rs: float = ruleset.run_step_seconds if ruleset != null else 0.12
			d["walk_speed_mps"] = cs / ws
			d["run_speed_mps"] = cs / rs
	d["walk_step_seconds"] = cs / float(d["walk_speed_mps"])
	d["run_step_seconds"] = cs / float(d["run_speed_mps"])
	return d


## Does resolved feel [param d] walk the hero freely ([HeroMover]) rather than a cell per step?
static func is_free(d: Dictionary) -> bool:
	return String(d.get("movement", "")) == MOVEMENT_FREE


## One line of numbers for logs / the A/B label.
static func describe(d: Dictionary) -> String:
	return "%s (%s): walk %.3f m/s (%.3f s/cell, clip x%.2f), run %.3f m/s (%.3f s/cell, clip x%.2f), %s glide, turn %.2f s%s, cam pitch %.0f fov %.0f dist %.1f %s rate %.1f lead %.2f s<=%.1f m" % [
		d["name"], d["movement"], d["walk_speed_mps"], d["walk_step_seconds"], d["walk_clip_rate"],
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
	_label.text = "Feel [F8] %d/%d: %s  (%s, walk %.2f m/s, run %.2f m/s, cam %.0f/%.0f deg %.1f m)" % [
		PRESET_ORDER.find(_active) + 1, PRESET_ORDER.size(), _active, d["movement"], d["walk_speed_mps"],
		d["run_speed_mps"], d["cam_pitch_deg"], d["cam_fov_deg"], d["cam_distance"]]


func _ruleset_or_null() -> StoryRuleset:
	var story := get_node_or_null("/root/StoryController")
	if story != null and story.has_method(&"ruleset"):
		return story.ruleset()
	return null
