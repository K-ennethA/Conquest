extends Node3D

class_name HealthBar

# 3D Health bar that floats above units

@onready var background: MeshInstance3D = $Background
@onready var health_fill: MeshInstance3D = $HealthFill
@onready var label: Label3D = $Label

# Bar dimensions (kept as constants so update_health() doesn't re-derive them)
const BG_SIZE := Vector2(1.5, 0.32)
const FILL_MAX_WIDTH := 1.4  # BG_SIZE.x minus a thin bronze border margin
const FILL_HEIGHT := 0.26

# HP thresholds for color transitions
const HP_THRESHOLD_HIGH := 0.5
const HP_THRESHOLD_MID := 0.25

const COLOR_HIGH := Color(0.30, 0.72, 0.28, 1.0)   # Green - healthy
const COLOR_MID := Color(0.92, 0.62, 0.13, 1.0)    # Amber - matches the fantasy UI vibe
const COLOR_LOW := Color(0.82, 0.18, 0.16, 1.0)    # Red - critical

# --- Status pips -------------------------------------------------------------
# A small row of billboarded coloured pips floating just ABOVE the bar, one per
# active StatusCondition, coloured through [StatusVisuals] -- the world-space
# sibling of TileEffectOverlay's per-tile pip row, and of the status chips in
# UnitInfoPanel / UnitHoverPanel. Same shared vocabulary, so "Ensnared" is the
# same violet on the map as it is in the panels.
#
# The pips live under their own child Node3D at a FIXED local offset, so a unit
# with no statuses gets no nodes and the bar itself never moves (no layout shift).
const STATUS_PIP_SIZE := 0.16
const STATUS_PIP_SPACING := 0.19  # world units between adjacent pip centers on X
const STATUS_PIP_Y := 0.30        # clears the 0.32-tall bar (half-height 0.16)

## Sentinel for _status_signature. Real signatures are "id:turns" entries joined
## by "|" (and "" for an empty list), so this can never collide with one -- which
## makes the first refresh after _ready or a rebind always take the rebuild path.
const SIGNATURE_UNSET := "<unset>"

var _background_material: StandardMaterial3D
var _health_material: StandardMaterial3D

## Parent of the pip row. Created once in _ready and then only ever has its
## children swapped, so the bar's own node layout is untouched.
var _status_root: Node3D = null

## Cheap change-detector: "id:turns|id:turns|…" for the statuses currently drawn.
## _refresh_status_pips() rebuilds ONLY when this string changes, so the refresh
## beats below can fire freely (several times per action) without any node churn.
## Seeded to a value no real signature can equal so the first refresh always runs.
var _status_signature: String = SIGNATURE_UNSET

# The unit this bar tracks. Bound via bind_unit() so the bar refreshes itself the
# instant HP changes, instead of relying on the UnitVisualManager -> unit
# ._on_health_changed indirection (which silently no-ops if the unit never
# resolved its visual_manager -- the "bar stays full green while losing HP" bug).
var _bound_unit = null

func _ready():
	_setup_materials()
	_setup_meshes()
	_setup_status_pips()
	# If bind_unit ran before _ready (materials/meshes not built yet), paint now.
	if _bound_unit != null:
		_refresh_from_unit()
	_refresh_status_pips()

## Track [param unit] directly: connect to its stat signal and refresh on every HP
## change. Idempotent and safe to call before or after _ready.
func bind_unit(unit) -> void:
	_bound_unit = unit
	if unit != null and unit.unit_stats != null:
		if not unit.unit_stats.health_changed.is_connected(_on_bound_health_changed):
			unit.unit_stats.health_changed.connect(_on_bound_health_changed)
	# A new unit means a whole new status list; force the next refresh to rebuild.
	_status_signature = SIGNATURE_UNSET
	_refresh_from_unit()
	_refresh_status_pips()

func _on_bound_health_changed(_old_health: int, _new_health: int) -> void:
	_refresh_from_unit()
	# HP changing is itself a status beat: a burn/poison tick lands as damage, and
	# the condition that caused it may have just expired in the same resolution.
	_refresh_status_pips()

func _refresh_from_unit() -> void:
	# Guard: unit freed, or _ready hasn't built the materials/meshes yet.
	if not is_instance_valid(_bound_unit) or _health_material == null:
		return
	var mx: int = _bound_unit.max_health
	if mx <= 0:
		return
	var cur: int = _bound_unit.current_health
	update_health(float(cur) / float(mx), cur, mx)

func _setup_materials():
	# Background material: dark bronze frame so the bar reads as a border, not a void
	_background_material = StandardMaterial3D.new()
	# OPAQUE "depleted" track. Must be fully opaque so the terrain/units behind the
	# bar never bleed through the empty portion (the "shows the map colour when it's
	# clear" report). A dark crimson also reads as lost health, so a low bar is
	# clearly a health bar (green fill over red track) rather than a stray sliver.
	_background_material.albedo_color = Color(0.16, 0.04, 0.05, 1.0)
	_background_material.flags_transparent = false
	_background_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_background_material.flags_unshaded = true
	_background_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_background_material.billboard_keep_scale = true
	_background_material.render_priority = 1

	# Health fill material (classic RPG style, recolored per current HP)
	_health_material = StandardMaterial3D.new()
	_health_material.albedo_color = COLOR_HIGH
	_health_material.flags_unshaded = true
	_health_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_health_material.billboard_keep_scale = true
	_health_material.render_priority = 2

func _setup_meshes():
	# Create background quad (dark bronze frame, sized for readability at camera distance)
	var bg_mesh = QuadMesh.new()
	bg_mesh.size = BG_SIZE
	background.mesh = bg_mesh
	background.material_override = _background_material
	# A UI overlay bar must never cast shadows onto the map (it billboards + is
	# unshaded, so a cast shadow is just a floating dark rectangle artifact).
	background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Create health fill quad (fits inside background, leaving a thin border visible)
	var health_mesh = QuadMesh.new()
	health_mesh.size = Vector2(FILL_MAX_WIDTH, FILL_HEIGHT)
	health_fill.mesh = health_mesh
	health_fill.material_override = _health_material
	health_fill.position.z = 0.01  # Slightly in front of background
	health_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Fire-Emblem style: the map bar shows HP as a pure colored bar, no numbers.
	# The Label3D node still exists in HealthBar.tscn, so hide it here rather
	# than populating it - exact HP lives in the unit info panel / combat
	# forecast, which are already the source of truth for numeric HP.
	if label:
		label.visible = false
		label.text = ""

func update_health(percentage: float, current: int, maximum: int):
	"""Update health bar display"""
	# Clamp percentage
	percentage = clamp(percentage, 0.0, 1.0)

	# Update fill width, keeping it left-aligned within the background frame
	if health_fill and health_fill.mesh:
		var mesh = health_fill.mesh as QuadMesh
		mesh.size.x = FILL_MAX_WIDTH * percentage
		health_fill.position.x = (FILL_MAX_WIDTH * percentage - FILL_MAX_WIDTH) * 0.5

	# Update color based on health percentage: green -> amber -> red
	if _health_material:
		if percentage > HP_THRESHOLD_HIGH:
			_health_material.albedo_color = COLOR_HIGH
		elif percentage > HP_THRESHOLD_MID:
			_health_material.albedo_color = COLOR_MID
		else:
			_health_material.albedo_color = COLOR_LOW

	# No numeric text on the map bar (Fire Emblem style) - current/maximum are
	# intentionally unused here; the bar's fill/color is the only readout.
	# Numeric HP is shown in the unit info panel and combat forecast instead.

func set_visible_state(visible: bool):
	"""Show or hide the health bar"""
	self.visible = visible


# --- Status pips --------------------------------------------------------------

## Create the pip row's parent and subscribe to the beats that can change a
## unit's status list.
##
## REFRESH STRATEGY (why there is no _process here): the status layer exposes no
## "statuses changed" signal today, so instead of polling every frame per unit --
## which would cost a controller walk per bar per frame -- we refresh on the
## discrete GameEvents beats where a status can actually appear, tick, or expire:
##
##   * unit_stats.health_changed  - already bound; covers tick damage/heal
##   * GameEvents.turn_started / turn_ended - StatusController.tick_all runs here
##   * GameEvents.unit_action_completed - a move just resolved (may have inflicted)
##   * GameEvents.unit_moved - stepping onto a trap tile inflicts on entry
##
## Those are global signals, so every bar wakes on each one; that is made free by
## the _status_signature guard in _refresh_status_pips(), which turns an unchanged
## status list into a string compare and an early return. If the status layer
## later gains a per-unit changed signal, connect it in bind_unit() and these
## broad beats can be dropped.
func _setup_status_pips() -> void:
	if _status_root == null or not is_instance_valid(_status_root):
		_status_root = Node3D.new()
		_status_root.name = "StatusPips"
		_status_root.position = Vector3(0.0, STATUS_PIP_Y, 0.02)
		add_child(_status_root)

	if GameEvents == null:
		return
	if not GameEvents.turn_started.is_connected(_on_status_turn_beat):
		GameEvents.turn_started.connect(_on_status_turn_beat)
	if not GameEvents.turn_ended.is_connected(_on_status_turn_beat):
		GameEvents.turn_ended.connect(_on_status_turn_beat)
	if not GameEvents.unit_action_completed.is_connected(_on_status_action_beat):
		GameEvents.unit_action_completed.connect(_on_status_action_beat)
	if not GameEvents.unit_moved.is_connected(_on_status_move_beat):
		GameEvents.unit_moved.connect(_on_status_move_beat)


func _on_status_turn_beat(_unit) -> void:
	_refresh_status_pips()


func _on_status_action_beat(_unit, _action_type) -> void:
	_refresh_status_pips()


func _on_status_move_beat(_unit, _from_position, _to_position) -> void:
	_refresh_status_pips()


## "id:turns|id:turns|…" for [param conditions]. Any change in which statuses are
## active, their order, or their remaining turns produces a different string.
func _status_signature_for(conditions: Array) -> String:
	var parts: PackedStringArray = []
	for condition in conditions:
		var id_text: String = "?"
		if typeof(condition) == TYPE_OBJECT and "id" in condition:
			id_text = String(condition.id)
		parts.append("%s:%d" % [id_text, StatusVisuals.turns_left_of(condition)])
	return "|".join(parts)


## Rebuild the pip row from the bound unit's active conditions -- but only when
## the list actually changed. No statuses (or no StatusController at all) leaves
## the row empty, which is exactly today's appearance.
func _refresh_status_pips() -> void:
	if _status_root == null or not is_instance_valid(_status_root):
		return

	# Null-safe all the way down: a freed unit, a unit with no controller, or an
	# empty list all come back as an empty array.
	var conditions: Array = StatusVisuals.active_conditions(_bound_unit)

	var signature: String = _status_signature_for(conditions)
	if signature == _status_signature:
		return
	_status_signature = signature

	for child in _status_root.get_children():
		child.queue_free()
	if conditions.is_empty():
		return

	# Cap the row: past MAX_PIPS the final slot becomes a neutral overflow marker
	# so a heavily-afflicted unit never grows an unbounded ribbon of pips.
	var total: int = conditions.size()
	var shown: int = StatusVisuals.shown_count(total)
	var hidden: int = StatusVisuals.hidden_count(total)
	var slots: int = shown + (1 if hidden > 0 else 0)
	if slots <= 0:
		return

	# Center the row over the bar: pip i sits at (i - (n-1)/2) * spacing on X.
	var x0: float = -0.5 * float(slots - 1) * STATUS_PIP_SPACING
	for i in range(shown):
		var info: Dictionary = StatusVisuals.info_for(conditions[i])
		var color: Color = info.get("color", StatusVisuals.OVERFLOW_COLOR)
		_status_root.add_child(_make_status_pip(color, x0 + float(i) * STATUS_PIP_SPACING))
	if hidden > 0:
		_status_root.add_child(
			_make_status_pip(StatusVisuals.OVERFLOW_COLOR, x0 + float(shown) * STATUS_PIP_SPACING))


## One pip quad tinted [param color], placed at [param x] in the row's local space.
func _make_status_pip(color: Color, x: float) -> MeshInstance3D:
	var pip := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(STATUS_PIP_SIZE, STATUS_PIP_SIZE)
	pip.mesh = mesh
	pip.position = Vector3(x, 0.0, 0.0)

	# Same billboard recipe as the bar itself (unshaded + BILLBOARD_ENABLED +
	# keep_scale), so the pips face the camera and hold a constant on-screen size
	# exactly like the bar they sit on.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.flags_unshaded = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.render_priority = 3  # above the bar's background (1) and fill (2)
	pip.material_override = mat
	return pip