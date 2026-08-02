extends Node

## Autoload [code]MobileDisplay[/code]: the whole of the project's mobile display story --
## content-scale selection and safe-area insets -- plus the mount point for the touch
## gesture layer.
##
## [b]Desktop is a guaranteed no-op.[/b] Every runtime path in this script returns
## immediately unless [method is_mobile] (i.e. [code]OS.has_feature("mobile")[/code]) is
## true, and headless runs bail before that. Nothing here is feature-tagged in
## [code]project.godot[/code]; the branch is at runtime so one build behaves correctly
## wherever it lands.
##
## [b]1. Content scale.[/b] [code]window/stretch/mode="canvas_items"[/code] handles aspect
## ratio but not pixel DENSITY: the 1280x720 design canvas stretched onto a 400+ DPI phone
## puts a 44px hit target at roughly 4mm, well under the ~7mm touch guideline.
## [method pick_content_scale_factor] turns DPI + screen size into a
## [member Window.content_scale_factor], clamped hard so a bad DPI report can never make
## the HUD swallow the board.
##
## [b]2. Safe area.[/b] [method apply_safe_area] pushes a container in from notches, punch
## holes and gesture bars using [method DisplayServer.get_display_safe_area]. It is applied
## in exactly two ways, so no screen copy-pastes the maths:
##   - the battle HUD calls it explicitly on its outermost [MarginContainer]
##     ([code]UILayoutManager._apply_safe_area[/code]);
##   - every MENU is covered automatically -- this autoload watches for [Control] scene
##     roots being added under [code]/root[/code] and insets them, which is why no menu
##     scene needed editing.
##
## [b]3. Gestures.[/b] [TouchInputAdapter] is mounted here as a child, on every platform,
## because it also serves trackpad pinch on desktop and costs nothing when no touch
## arrives. See that class for the mouse-emulation decision.
##
## [b]Not done here:[/b] on-device tuning. The constants below are derived from a viewing
## distance model, not measured on hardware -- no device was available. They are the
## single place to retune once one is.

## The canvas the UI was authored against ([code]window/size/viewport_*[/code]).
const DESIGN_SIZE := Vector2i(1280, 720)

## Density the UI reads correctly at on a desktop monitor. 96 DPI is the Windows/CSS
## reference and matches the machine this HUD was designed on.
const REFERENCE_DPI := 96.0

## Phones are held at roughly half a monitor's viewing distance, so matching a desktop's
## PHYSICAL text size 1:1 would waste half the screen. 0.5 targets the same ANGULAR size
## instead, which is what actually governs legibility.
const VIEW_DISTANCE_RATIO := 0.5

## Hard clamps. 1.0 = never shrink the UI below the authored desktop size (a tablet needs
## no help); 1.75 = never let a mis-reported DPI leave no room for the board.
const SCALE_MIN := 1.0
const SCALE_MAX := 1.75

## Snap the result so two near-identical devices don't land on 1.3712 vs 1.3698 and produce
## different screenshots for no reason.
const SCALE_STEP := 0.05

## Metadata key holding the insets this helper last applied to a node, so re-applying
## (orientation change, re-entering a scene) replaces rather than accumulates.
const APPLIED_META := "_mobile_safe_area_applied"

## The content scale factor actually applied this run. 1.0 on desktop. Read by
## [method compute_safe_area_margins] to convert physical inset pixels into UI pixels.
static var _ui_scale: float = 1.0

var _gestures: TouchInputAdapter = null


func _ready() -> void:
	name = "MobileDisplay"

	_mount_gesture_adapter()

	if not is_mobile():
		return
	_apply_content_scale()

	var tree := get_tree()
	if tree == null:
		return
	# Menus are separate scenes with no shared base class, so rather than editing each one
	# we inset any Control scene root as it is installed under /root.
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	if tree.current_scene is Control:
		call_deferred("apply_safe_area", tree.current_scene)


# --- Platform ---------------------------------------------------------------

## True on Android / iOS exports. The single gate every runtime path here sits behind.
static func is_mobile() -> bool:
	return OS.has_feature("mobile")


## Headless (CI, GUT) has no real display server; every DisplayServer query below would
## return junk, so callers bail on this first.
static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


## The content scale factor in force. 1.0 unless [method _apply_content_scale] ran.
static func ui_scale() -> float:
	return _ui_scale


# --- 1. Content scale -------------------------------------------------------

## The multiplier [code]canvas_items[/code] stretch already applies on this screen: with
## [code]aspect="expand"[/code] Godot scales by the SMALLER axis ratio and reveals more
## world on the other. Pure; 1.0 for a degenerate screen size.
static func stretch_scale(screen_size: Vector2i, design_size: Vector2i = DESIGN_SIZE) -> float:
	if screen_size.x <= 0 or screen_size.y <= 0 or design_size.x <= 0 or design_size.y <= 0:
		return 1.0
	return minf(
		float(screen_size.x) / float(design_size.x),
		float(screen_size.y) / float(design_size.y))


## PURE: density + resolution in, [member Window.content_scale_factor] out.
##
## A UI pixel's physical size is [code]stretch_scale / dpi[/code] inches. Dividing that by
## the desktop reference ([code]1 / REFERENCE_DPI[/code]) gives how much SMALLER the UI is
## here than on the machine it was designed on; correcting by that ratio, discounted by
## [constant VIEW_DISTANCE_RATIO] for the closer holding distance, is the factor.
##
## [codeblock]
##   factor = (dpi / REFERENCE_DPI) / stretch_scale * VIEW_DISTANCE_RATIO
## [/codeblock]
##
## Snapped then clamped, so the return is always within [constant SCALE_MIN] ..
## [constant SCALE_MAX]. Any nonsense input (DPI <= 0, which is what a platform that cannot
## report density returns; empty screen) yields exactly 1.0 -- the authored desktop look.
static func pick_content_scale_factor(dpi: int, screen_size: Vector2i,
		design_size: Vector2i = DESIGN_SIZE) -> float:
	if dpi <= 0:
		return 1.0
	if screen_size.x <= 0 or screen_size.y <= 0:
		return 1.0
	var s: float = stretch_scale(screen_size, design_size)
	if s <= 0.0:
		return 1.0
	var raw: float = (float(dpi) / REFERENCE_DPI) / s * VIEW_DISTANCE_RATIO
	return clampf(snappedf(raw, SCALE_STEP), SCALE_MIN, SCALE_MAX)


func _apply_content_scale() -> void:
	if is_headless():
		return
	var win := get_window()
	if win == null:
		return
	var screen_id: int = DisplayServer.window_get_current_screen()
	var dpi: int = DisplayServer.screen_get_dpi(screen_id)
	var screen: Vector2i = DisplayServer.screen_get_size(screen_id)
	_ui_scale = pick_content_scale_factor(dpi, screen)
	win.content_scale_factor = _ui_scale


# --- 2. Safe area -----------------------------------------------------------

## PURE: safe rect + window rect in, per-edge margins out (in UI pixels).
##
## [param safe_rect] is what [method DisplayServer.get_display_safe_area] reports -- the
## sub-rectangle of the screen not covered by a notch, punch hole, status bar or gesture
## bar -- in the same coordinate space as [param window_rect]. Each edge inset is how far
## the safe rect is inside the window on that side, never negative (a safe area REPORTED as
## larger than the window means "nothing is covered", not "expand into the bezel").
##
## [param ui_scale] converts physical pixels to the UI pixels a [Control] is laid out in;
## the result is rounded UP so a rounding error can never leave a pixel under the notch.
##
## An empty [param safe_rect] -- what every desktop platform returns -- gives all zeros,
## which is the whole reason desktop needs no special-casing downstream.
static func safe_area_margins(safe_rect: Rect2i, window_rect: Rect2i,
		ui_scale_factor: float = 1.0) -> Dictionary:
	var zero: Dictionary = {"left": 0, "top": 0, "right": 0, "bottom": 0}
	if safe_rect.size.x <= 0 or safe_rect.size.y <= 0:
		return zero
	if window_rect.size.x <= 0 or window_rect.size.y <= 0:
		return zero

	var scale: float = ui_scale_factor
	if not is_finite(scale) or scale <= 0.0:
		scale = 1.0

	var left: int = maxi(0, safe_rect.position.x - window_rect.position.x)
	var top: int = maxi(0, safe_rect.position.y - window_rect.position.y)
	var right: int = maxi(0, (window_rect.position.x + window_rect.size.x)
		- (safe_rect.position.x + safe_rect.size.x))
	var bottom: int = maxi(0, (window_rect.position.y + window_rect.size.y)
		- (safe_rect.position.y + safe_rect.size.y))

	return {
		"left": ceili(float(left) / scale),
		"top": ceili(float(top) / scale),
		"right": ceili(float(right) / scale),
		"bottom": ceili(float(bottom) / scale),
	}


## Live safe-area insets for this window, in UI pixels. All zeros on desktop and headless.
static func compute_safe_area_margins() -> Dictionary:
	var zero: Dictionary = {"left": 0, "top": 0, "right": 0, "bottom": 0}
	if not is_mobile() or is_headless():
		return zero
	var window_rect := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	return safe_area_margins(DisplayServer.get_display_safe_area(), window_rect, _ui_scale)


## THE reusable entry point. Inset [param target] away from notches / home bars.
##
## Accepts either a [MarginContainer] (adds to its margin constants, preserving the
## authored values) or any other [Control] (shifts its anchor offsets inward). Idempotent:
## a second call replaces the previous insets instead of stacking them, so an orientation
## change or a re-entered scene stays correct.
##
## Desktop and headless return before touching anything.
static func apply_safe_area(target: Control) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not is_mobile() or is_headless():
		return
	var margins: Dictionary = compute_safe_area_margins()
	if target is MarginContainer:
		_apply_margin_container(target as MarginContainer, margins)
	else:
		_apply_control_offsets(target, margins)


static func _apply_margin_container(mc: MarginContainer, margins: Dictionary) -> void:
	# The authored margins are whatever the container had BEFORE any inset of ours, which
	# is what get_theme_constant reports on the first call. Cache them so repeat calls add
	# to the original rather than to our own previous result.
	var base: Dictionary
	if mc.has_meta(APPLIED_META):
		base = mc.get_meta(APPLIED_META)
	else:
		base = {
			"left": mc.get_theme_constant("margin_left"),
			"top": mc.get_theme_constant("margin_top"),
			"right": mc.get_theme_constant("margin_right"),
			"bottom": mc.get_theme_constant("margin_bottom"),
		}
		mc.set_meta(APPLIED_META, base)
	var edges: Array[String] = ["left", "top", "right", "bottom"]
	for edge in edges:
		mc.add_theme_constant_override("margin_" + edge,
			int(base[edge]) + int(margins[edge]))


static func _apply_control_offsets(c: Control, margins: Dictionary) -> void:
	# Undo whatever we applied last time before applying the new values, so this is a SET
	# rather than an accumulate.
	var prev: Dictionary = {"left": 0, "top": 0, "right": 0, "bottom": 0}
	if c.has_meta(APPLIED_META):
		prev = c.get_meta(APPLIED_META)
	c.offset_left += int(margins["left"]) - int(prev["left"])
	c.offset_top += int(margins["top"]) - int(prev["top"])
	c.offset_right -= int(margins["right"]) - int(prev["right"])
	c.offset_bottom -= int(margins["bottom"]) - int(prev["bottom"])
	c.set_meta(APPLIED_META, margins)


# --- Automatic menu coverage ------------------------------------------------

## Only ever connected on mobile. Scene roots are direct children of the tree root, so the
## parent check keeps this off the hot path for the thousands of ordinary nodes a battle
## scene adds.
func _on_node_added(node: Node) -> void:
	var tree := get_tree()
	if tree == null or node.get_parent() != tree.root:
		return
	if not (node is Control):
		return
	# Deferred: a menu that calls set_anchors_preset() in its own _ready would otherwise
	# overwrite the offsets we just set.
	call_deferred("apply_safe_area", node)


# --- Gesture layer mount ----------------------------------------------------

func _mount_gesture_adapter() -> void:
	if is_headless():
		return
	_gestures = TouchInputAdapter.new()
	_gestures.name = "TouchInputAdapter"
	add_child(_gestures)
