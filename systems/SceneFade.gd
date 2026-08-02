extends CanvasLayer

## Autoload that fades the screen IN on every scene arrival, with ZERO call-site changes.
##
## HOW IT DETECTS A SCENE SWAP: mirrors AudioManager's existing, working pattern (see
## [code]game/audio/AudioManager.gd[/code] -- [method AudioManager._on_scene_tree_node_added]
## and its class-doc note on menu-music scene detection) rather than inventing a new one:
## every scene root -- the first boot's main scene AND every future
## [code]change_scene_to_file[/code] / [code]change_scene_to_packed[/code] target -- lands as
## a direct child of the [SceneTree] root, so watching [signal SceneTree.node_added] for that
## shape (`node.get_parent() == get_tree().root`) catches every arrival with no per-scene
## wiring. SceneFade is registered LAST in [code][autoload][/code] (right after
## PlayerProfile) specifically so no earlier autoload's own node_added fires this watcher
## before it is connected, and no later one fires it spuriously once it is.
##
## Draws a single full-rect black [ColorRect] on a dedicated [CanvasLayer] at
## [constant LAYER_INDEX] -- above every HUD/menu/overlay layer in the project (the highest
## in use elsewhere is TurnTransition's 128) -- and only ever tweens its `modulate:a`.
## `mouse_filter` is IGNORE throughout, so this never blocks input even while opaque.
##
## PUBLIC API for FUTURE call sites: [method change_scene] fades out then
## `change_scene_to_file`s. Nothing in the project calls it yet -- every existing
## `change_scene_to_file`/`change_scene_to_packed` call site is untouched and still gets its
## fade-IN for free via the node_added watcher above; migrating them is future work.
##
## HEADLESS: a test/CI run has no viewport to fade. Cached once in [method _ready] (matches
## the project's existing headless convention -- see [code]game/items/ItemToast.gd[/code],
## [code]game/profile/PlayerProfile.gd[/code]): the [ColorRect] is never built and the
## node_added watcher is never connected, so [method change_scene] falls straight through to
## `change_scene_to_file` on the same call with no tween and no `await` anywhere in this
## script -- nothing here can ever suspend on a signal that has no listener to fire it, so a
## soak run or a GUT suite can never hang on this autoload.
##
## ANIMATIONS OFF: read null-safely off the GameSettings autoload the same way
## TurnTransition/UltimateCutIn do (`typeof(GameSettings) == TYPE_OBJECT`; absent -> ON), so a
## fade is either its full authored duration or instant (alpha snapped, no tween built at all).

## Above every other overlay layer in the project (TurnTransition's 128 is the next-highest).
const LAYER_INDEX: int = 200

## Fade-IN duration (seconds) on scene arrival -- see class doc.
const FADE_IN_TIME: float = 0.25
## Fade-OUT duration (seconds) before [method change_scene] swaps the scene.
const FADE_OUT_TIME: float = 0.2

var _rect: ColorRect = null
var _tween: Tween = null

## True on a headless run (soak harness, GUT). Cached once in [method _ready]; see class doc.
var _headless: bool = false

## Guards [method change_scene] against re-entrancy: a second call while a previous one is
## still fading out is a no-op rather than stacking scene swaps.
var _changing_scene: bool = false


func _ready() -> void:
	name = "SceneFade"
	layer = LAYER_INDEX
	# Keep fading even if something pauses the tree during a scene hand-off (mirrors
	# ItemToast's reasoning for the same flag).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_headless = DisplayServer.get_name() == "headless"
	if _headless:
		return

	_build_rect()

	# Connect BEFORE the project's main scene is ever added (autoloads _ready before the main
	# scene is instanced), so even the very first boot scene fades in. See class doc.
	get_tree().node_added.connect(_on_scene_tree_node_added)


func _build_rect() -> void:
	_rect = ColorRect.new()
	_rect.name = "SceneFadeRect"
	_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Start opaque: the very first frame (before the main scene lands and triggers the
	# fade-in below) should read as black, not a flash of whatever the viewport clears to.
	_rect.modulate.a = 1.0
	add_child(_rect)


# --- Public API --------------------------------------------------------------------------

## Fade out over [constant FADE_OUT_TIME], then `change_scene_to_file(path)`. For FUTURE call
## sites -- see class doc; migrate none now. Re-entrancy guarded (see [member _changing_scene]).
## Headless / animations-off / no viewport: no tween, no await -- changes the scene on this
## same call.
func change_scene(path: String) -> void:
	if _changing_scene:
		return
	_changing_scene = true

	if _headless or _rect == null or not _animations_on():
		_changing_scene = false
		get_tree().change_scene_to_file(path)
		return

	_kill_tween()
	_rect.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 1.0, FADE_OUT_TIME)
	# tween_callback (not await) so this never suspends the caller and can never hang
	# headless -- see class doc.
	_tween.tween_callback(_finish_change_scene.bind(path))


func _finish_change_scene(path: String) -> void:
	_changing_scene = false
	get_tree().change_scene_to_file(path)


# --- Scene-swap detection (mirrors AudioManager -- see class doc) ------------------------

func _on_scene_tree_node_added(node: Node) -> void:
	if node.get_parent() == get_tree().root:
		_fade_in()


func _fade_in() -> void:
	if _rect == null:
		return
	_kill_tween()
	_rect.modulate.a = 1.0
	if not _animations_on():
		_rect.modulate.a = 0.0
		return
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 0.0, FADE_IN_TIME)


# --- Helpers -------------------------------------------------------------------------------

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## Null-safe GameSettings read, matching TurnTransition/UltimateCutIn's convention exactly
## (absent autoload -> behave as animations-on).
func _animations_on() -> bool:
	if typeof(GameSettings) == TYPE_OBJECT:
		return GameSettings.animations_on()
	return true
