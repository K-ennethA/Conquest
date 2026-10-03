extends CanvasLayer
class_name WorldLookPresetCycler

## DEBUG-ONLY look A/B harness (research godot-world-feel.md item 1). Press F7 in any
## battle / overworld / duel launch to cycle [constant WorldLook.LOOK_PRESET_ORDER]
## ("current" = pre-retune values, "new" = shipped defaults, plus labeled variants) on
## every [WorldLook] in the tree; a small corner label names the active preset.
##
## Spawned by [method WorldLook.setup] via [method attach] -- one instance under /root,
## only in debug builds with a real display (release exports and headless test runs never
## create it). The input action "debug_cycle_look" is registered at runtime, so the
## project's [input] map and its rebinding UI stay untouched. F7 is bound by nothing in
## game/, systems/ or menus/ (only stray dev_scripts/ test scenes read it).

const NODE_NAME := "WorldLookPresetCycler"
const ACTION := &"debug_cycle_look"
const KEY := KEY_F7

static var _instance: WorldLookPresetCycler = null

var _index: int = 0
var _label: Label = null


static func enabled() -> bool:
	return OS.is_debug_build() and DisplayServer.get_name() != "headless"


## Ensure the single cycler exists and hand [param look] the active preset (so a map
## load keeps whatever the artist is comparing).
static func attach(look: WorldLook) -> void:
	if not enabled() or look == null or not look.is_inside_tree():
		return
	if _instance == null or not is_instance_valid(_instance):
		_instance = WorldLookPresetCycler.new()
		_instance.name = NODE_NAME
		look.get_tree().root.add_child.call_deferred(_instance)
	_instance.adopt(look)


func _init() -> void:
	layer = 128
	_index = maxi(WorldLook.LOOK_PRESET_ORDER.find(WorldLook.LOOK_PRESET_DEFAULT), 0)


func _ready() -> void:
	ensure_action()
	_label = Label.new()
	_label.name = "PresetLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 3)
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 8)
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


func active_preset() -> String:
	return WorldLook.LOOK_PRESET_ORDER[_index]


## Step to the next preset and apply it to every WorldLook in the tree.
func cycle() -> void:
	_index = (_index + 1) % WorldLook.LOOK_PRESET_ORDER.size()
	var tree := get_tree()
	if tree != null:
		for n in tree.get_nodes_in_group(&"world_look"):
			if n is WorldLook:
				(n as WorldLook).apply_look_preset(active_preset())
				print("[WorldLook A/B] ", (n as WorldLook).dump_state())
	_refresh_label()


func adopt(look: WorldLook) -> void:
	if look.look_preset != active_preset():
		look.apply_look_preset(active_preset())


func _refresh_label() -> void:
	if _label == null:
		return
	var p := active_preset()
	var d: Dictionary = WorldLook.LOOK_PRESETS[p]
	var blend := "softlight" if int(d["glow_blend_mode"]) == Environment.GLOW_BLEND_MODE_SOFTLIGHT else "screen"
	_label.text = "Look [F7] %d/%d: %s  (%s, thr %.2f)" % [_index + 1, WorldLook.LOOK_PRESET_ORDER.size(), p,
		blend, float(d["glow_hdr_threshold"])]
