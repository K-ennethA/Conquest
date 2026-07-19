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

var _background_material: StandardMaterial3D
var _health_material: StandardMaterial3D

# The unit this bar tracks. Bound via bind_unit() so the bar refreshes itself the
# instant HP changes, instead of relying on the UnitVisualManager -> unit
# ._on_health_changed indirection (which silently no-ops if the unit never
# resolved its visual_manager -- the "bar stays full green while losing HP" bug).
var _bound_unit = null

func _ready():
	_setup_materials()
	_setup_meshes()
	# If bind_unit ran before _ready (materials/meshes not built yet), paint now.
	if _bound_unit != null:
		_refresh_from_unit()

## Track [param unit] directly: connect to its stat signal and refresh on every HP
## change. Idempotent and safe to call before or after _ready.
func bind_unit(unit) -> void:
	_bound_unit = unit
	if unit != null and unit.unit_stats != null:
		if not unit.unit_stats.health_changed.is_connected(_on_bound_health_changed):
			unit.unit_stats.health_changed.connect(_on_bound_health_changed)
	_refresh_from_unit()

func _on_bound_health_changed(_old_health: int, _new_health: int) -> void:
	_refresh_from_unit()

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

	# Create health fill quad (fits inside background, leaving a thin border visible)
	var health_mesh = QuadMesh.new()
	health_mesh.size = Vector2(FILL_MAX_WIDTH, FILL_HEIGHT)
	health_fill.mesh = health_mesh
	health_fill.material_override = _health_material
	health_fill.position.z = 0.01  # Slightly in front of background

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