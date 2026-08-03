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
# A small row of billboarded status BADGES floating just ABOVE the bar -- a coloured
# chip carrying the status' one-character glyph, and its stack count when it is
# stacked. Colour, glyph and grouping all come from [StatusVisuals], the world-space
# sibling of TileEffectOverlay's per-tile pip row and of the status chips in
# UnitInfoPanel / UnitHoverPanel. Same shared vocabulary, so "Ensnared" is the
# same violet on the map as it is in the panels.
#
# WHY A GLYPH AND NOT JUST A COLOUR (it used to be a bare coloured quad): at this size
# a hue on its own is not a readout. Two violets a few points apart are the same pip to
# a player mid-turn, poison had no table row at all so it drew as the neutral tan
# fallback, and none of it survives colour blindness. The glyph says which of five
# things is happening (damage over time / heal over time / guard / buff / debuff)
# before the colour is even resolved.
#
# WHY THE ROW IS GROUPED BY ID: three stacked Poisoned instances are ONE status at
# severity 3. Drawn per instance they filled the whole 4-slot budget with identical
# pips and pushed every OTHER status on the unit into the overflow marker -- so the
# row is built from [method StatusVisuals.group_by_id] and shows "◆3".
#
# The badges live under their own child Node3D at a FIXED local offset, so a unit
# with no statuses gets no nodes and the bar itself never moves (no layout shift).
const STATUS_PIP_SIZE := 0.20
const STATUS_PIP_SPACING := 0.24  # world units between adjacent pip centers on X
const STATUS_PIP_Y := 0.32        # clears the 0.32-tall bar (half-height 0.16)
## Glyph drawn on the chip. Dark ink with a thin pale outline, which is the one
## combination that stays legible on EVERY chip hue (a white glyph washes out on the
## pale buffs, a black one disappears on the deep debuffs).
const STATUS_GLYPH_FONT_SIZE := 44
const STATUS_GLYPH_PIXEL_SIZE := 0.0032
const STATUS_GLYPH_INK := Color(0.10, 0.06, 0.03, 1.0)
const STATUS_GLYPH_OUTLINE := Color(1.0, 0.97, 0.90, 0.75)

## Sentinel for _status_signature. Real signatures are "id:turns" entries joined
## by "|" (and "" for an empty list), so this can never collide with one -- which
## makes the first refresh after _ready or a rebind always take the rebuild path.
const SIGNATURE_UNSET := "<unset>"

# --- Terrain bonus tag -------------------------------------------------------
# A single billboarded green "+AVO N" Label3D floating just BELOW the bar, shown
# only while the bound unit stands on a tile that grants an evasion bonus (the
# Fire-Emblem tall-grass "avoid": TerrainStats.bonus_for(unit, "evasion") > 0).
# Terrain bonuses are computed on the fly, never stored as a status, so this is
# the world-space readout that lets the player SEE that a unit is harder to hit
# because of where it is standing. Created once and only toggled/retexted after,
# so it costs nothing when the unit is off grass.
const TERRAIN_TAG_Y := -0.28          # below the 0.32-tall bar, clear of it
const TERRAIN_TAG_FONT_SIZE := 40
const TERRAIN_TAG_PIXEL_SIZE := 0.005  # ~0.20 world-unit glyph height, pip-scale
const TERRAIN_LEAF_GREEN := Color("5fb84e")  # == ConquestTheme.EL_NATURE

var _background_material: StandardMaterial3D
var _health_material: StandardMaterial3D

# --- Incoming-damage preview band --------------------------------------------
# A blinking red band laid over the slice of the fill a pending move would remove,
# so an AoE that hits several units lights up EVERY victim's bar in the overworld
# (not just the one enemy the combat forecast card is showing). Driven by
# UnitVisualManager.preview_damage() while a move is being aimed; cleared the
# instant targeting ends. Built lazily -- a unit that is never in an AoE footprint
# pays for no nodes. The band sits just in front of the fill and blinks its alpha.
const DMG_BAND_COLOR := Color(0.98, 0.16, 0.13, 1.0)  # hot red -- "this much is about to go"
const DMG_BAND_MIN_ALPHA := 0.35
const DMG_BAND_BLINK_TIME := 0.45
var _dmg_band: MeshInstance3D = null
var _dmg_band_material: StandardMaterial3D = null
var _dmg_band_tween: Tween = null

## Green "+AVO N" tag; built once in _setup_terrain_tag, then only shown/hidden
## and re-texted. Null until _ready.
var _terrain_tag: Label3D = null

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
	_setup_terrain_tag()
	# If bind_unit ran before _ready (materials/meshes not built yet), paint now.
	if _bound_unit != null:
		_refresh_from_unit()
	_refresh_status_pips()
	_refresh_terrain_tag()

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
	_refresh_terrain_tag()

func _on_bound_health_changed(_old_health: int, _new_health: int) -> void:
	_refresh_from_unit()
	# HP changing is itself a status beat: a burn/poison tick lands as damage, and
	# the condition that caused it may have just expired in the same resolution.
	_refresh_status_pips()
	_refresh_terrain_tag()

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

	# The status layer DOES announce now (status_applied / status_ticked /
	# status_expired). These are the precise beats -- a status landing mid-move no
	# longer waits for the next turn/HP change to appear on the bar. The broad beats
	# above are KEPT as the safety net for anything that mutates the list without
	# going through StatusController (and cost nothing: the signature guard turns an
	# unchanged list into a string compare).
	if GameEvents.has_signal(&"status_applied") \
			and not GameEvents.status_applied.is_connected(_on_status_changed_beat):
		GameEvents.status_applied.connect(_on_status_changed_beat)
	if GameEvents.has_signal(&"status_expired") \
			and not GameEvents.status_expired.is_connected(_on_status_changed_beat):
		GameEvents.status_expired.connect(_on_status_changed_beat)


func _on_status_turn_beat(_unit) -> void:
	_refresh_status_pips()
	# A tile can gain/lose a passive bonus between turns (e.g. grass catching fire),
	# so re-check the terrain tag on the same turn beats as the pips.
	_refresh_terrain_tag()


## A status landed on / left SOME unit. Global like the other beats -- every bar wakes,
## and the signature guard makes all but the affected one an early return.
func _on_status_changed_beat(_unit, _condition) -> void:
	_refresh_status_pips()


func _on_status_action_beat(_unit, _action_type) -> void:
	_refresh_status_pips()
	# An action can displace a unit (knockback/pull) or alter its tile, either of
	# which changes the terrain bonus without a move_beat firing for this unit.
	_refresh_terrain_tag()


func _on_status_move_beat(_unit, _from_position, _to_position) -> void:
	_refresh_status_pips()
	# A unit can walk onto or off tall grass with no HP change, so the terrain tag
	# has to be re-evaluated on every move -- this is the beat that makes "+AVO"
	# appear the instant a unit steps into grass and vanish when it steps out.
	_refresh_terrain_tag()


## "id:turns:count|…" for the GROUPED conditions. Any change in which statuses are
## active, their order, their remaining turns, or their stack depth produces a
## different string -- so a poison deepening from x2 to x3 rebuilds the row.
func _status_signature_for(groups: Array) -> String:
	var parts: PackedStringArray = []
	for group in groups:
		var condition = group.get("condition", null)
		var id_text: String = "?"
		if typeof(condition) == TYPE_OBJECT and "id" in condition:
			id_text = String(condition.id)
		parts.append("%s:%d:%d" % [
			id_text, int(group.get("turns_left", 0)), int(group.get("count", 1))])
	return "|".join(parts)


## Rebuild the badge row from the bound unit's active conditions -- but only when
## the list actually changed. No statuses (or no StatusController at all) leaves
## the row empty, which is exactly today's appearance.
func _refresh_status_pips() -> void:
	if _status_root == null or not is_instance_valid(_status_root):
		return

	# Null-safe all the way down: a freed unit, a unit with no controller, or an
	# empty list all come back as an empty array. Grouped by id so severity renders
	# as one badge, not N identical ones.
	var groups: Array = StatusVisuals.group_by_id(
		StatusVisuals.active_conditions(_bound_unit))

	var signature: String = _status_signature_for(groups)
	if signature == _status_signature:
		return
	_status_signature = signature

	for child in _status_root.get_children():
		child.queue_free()
	if groups.is_empty():
		return

	# Cap the row: past MAX_PIPS the final slot becomes a neutral overflow marker
	# so a heavily-afflicted unit never grows an unbounded ribbon of badges.
	var total: int = groups.size()
	var shown: int = StatusVisuals.shown_count(total)
	var hidden: int = StatusVisuals.hidden_count(total)
	var slots: int = shown + (1 if hidden > 0 else 0)
	if slots <= 0:
		return

	# Center the row over the bar: badge i sits at (i - (n-1)/2) * spacing on X.
	var x0: float = -0.5 * float(slots - 1) * STATUS_PIP_SPACING
	for i in range(shown):
		var group: Dictionary = groups[i]
		var condition = group.get("condition", null)
		var info: Dictionary = StatusVisuals.info_for(condition)
		var color: Color = info.get("color", StatusVisuals.OVERFLOW_COLOR)
		var x: float = x0 + float(i) * STATUS_PIP_SPACING
		_status_root.add_child(_make_status_pip(color, x))
		var glyph: String = StatusVisuals.glyph_for(condition)
		var count: int = int(group.get("count", 1))
		if count > 1:
			glyph += str(count)
		_status_root.add_child(_make_status_glyph(glyph, x))
	if hidden > 0:
		var overflow_x: float = x0 + float(shown) * STATUS_PIP_SPACING
		_status_root.add_child(_make_status_pip(StatusVisuals.OVERFLOW_COLOR, overflow_x))
		_status_root.add_child(
			_make_status_glyph(StatusVisuals.overflow_label(hidden), overflow_x))


## The status' glyph (plus its stack count when stacked), drawn on the chip at
## [param x]. Same billboard recipe as the terrain tag, so it holds a constant
## on-screen size and never casts a shadow onto the map.
func _make_status_glyph(text: String, x: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = Vector3(x, 0.0, 0.01)  # just in front of the chip quad
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# NOTE: fixed_size stays OFF -- with it on, pixel_size * font_size stops mapping to
	# world units and the glyph renders screen-huge (the same trap documented on the
	# terrain tag below).
	label.font_size = STATUS_GLYPH_FONT_SIZE
	label.pixel_size = STATUS_GLYPH_PIXEL_SIZE
	label.modulate = STATUS_GLYPH_INK
	label.outline_modulate = STATUS_GLYPH_OUTLINE
	label.outline_size = 5
	label.render_priority = 5   # above bar bg (1), fill (2), chips (3), terrain tag (4)
	label.outline_render_priority = 4
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label


## One chip quad tinted [param color], placed at [param x] in the row's local space.
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


# --- Terrain bonus tag --------------------------------------------------------

## Build the "+AVO N" Label3D once. It uses the SAME overlay recipe as the bar
## (billboarded, unshaded, no cast shadow, constant on-screen size) so it faces
## the camera and never drops a floating shadow rectangle onto the map. Starts
## hidden; _refresh_terrain_tag drives its visibility and text.
func _setup_terrain_tag() -> void:
	if _terrain_tag != null and is_instance_valid(_terrain_tag):
		return
	_terrain_tag = Label3D.new()
	_terrain_tag.name = "TerrainAvoidTag"
	_terrain_tag.text = ""
	_terrain_tag.position = Vector3(0.0, TERRAIN_TAG_Y, 0.02)
	_terrain_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_terrain_tag.shaded = false
	# NOTE: do NOT set fixed_size -- with it on, pixel_size*font_size stops mapping to
	# world units and the label renders screen-huge (the "#AVO 15 plastered across the
	# whole map" bug). Left off, the tag is a ~0.20 world-unit billboarded label that
	# scales with the camera like every other world marker.
	_terrain_tag.font_size = TERRAIN_TAG_FONT_SIZE
	_terrain_tag.pixel_size = TERRAIN_TAG_PIXEL_SIZE
	_terrain_tag.modulate = TERRAIN_LEAF_GREEN
	# A dark outline keeps the green legible over both grass and bright tiles.
	_terrain_tag.outline_modulate = Color(0.05, 0.03, 0.0, 0.85)
	_terrain_tag.outline_size = 6
	_terrain_tag.render_priority = 4  # above bar background (1), fill (2), pips (3)
	_terrain_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_terrain_tag.visible = false
	add_child(_terrain_tag)


## Show "+AVO N" when the bound unit's tile grants an evasion bonus, hide it
## otherwise. Fully null-safe: a freed unit, an absent CombatServices, or a null
## board all resolve to a 0 bonus (hidden). TerrainStats.bonus_for reads the
## PASSIVE_WHILE_OCCUPYING tile effects under the unit -- tall grass -> +evasion.
func _refresh_terrain_tag() -> void:
	if _terrain_tag == null or not is_instance_valid(_terrain_tag):
		return
	if not is_instance_valid(_bound_unit):
		_terrain_tag.visible = false
		return
	var board = CombatServices.board() if CombatServices else null
	var avoid: int = TerrainStats.bonus_for(_bound_unit, "evasion", board)
	if avoid > 0:
		_terrain_tag.text = "+AVO %d" % avoid
		_terrain_tag.visible = true
	else:
		_terrain_tag.visible = false


# --- Incoming-damage preview band --------------------------------------------

## Lay a blinking red band over the [param amount] of HP a pending move would
## remove from the bound unit, so the overworld shows -- on every affected bar at
## once -- how much an AoE is about to take. amount <= 0 (a heal/miss/whiff) just
## clears the band. Fully null-safe; safe to call before _ready (meshes absent ->
## no-op until the next call once built).
func show_damage_preview(amount: int) -> void:
	if amount <= 0 or not is_instance_valid(_bound_unit):
		clear_damage_preview()
		return
	var mx: int = _bound_unit.max_health
	if mx <= 0:
		clear_damage_preview()
		return
	var cur: int = _bound_unit.current_health
	if cur <= 0:
		clear_damage_preview()
		return

	# Fractions along the bar: the band covers [remaining .. current], i.e. the
	# slice between where HP will land and where it is now.
	var cur_frac: float = clampf(float(cur) / float(mx), 0.0, 1.0)
	var rem_frac: float = clampf(float(cur - amount) / float(mx), 0.0, cur_frac)
	var span: float = cur_frac - rem_frac
	if span <= 0.001:
		clear_damage_preview()
		return

	_ensure_damage_band()
	var band_mesh := _dmg_band.mesh as QuadMesh
	band_mesh.size = Vector2(FILL_MAX_WIDTH * span, FILL_HEIGHT)
	# Fill maps fraction f -> x = -FILL_MAX_WIDTH/2 + FILL_MAX_WIDTH*f; centre the
	# band on the midpoint of [rem_frac, cur_frac].
	var mid: float = (rem_frac + cur_frac) * 0.5
	_dmg_band.position.x = -FILL_MAX_WIDTH * 0.5 + FILL_MAX_WIDTH * mid
	_dmg_band.visible = true
	_start_damage_blink()


## Remove the preview band (kills its blink tween). Idempotent.
func clear_damage_preview() -> void:
	if _dmg_band_tween != null and _dmg_band_tween.is_valid():
		_dmg_band_tween.kill()
	_dmg_band_tween = null
	if _dmg_band != null and is_instance_valid(_dmg_band):
		_dmg_band.visible = false


func _ensure_damage_band() -> void:
	if _dmg_band != null and is_instance_valid(_dmg_band):
		return
	_dmg_band_material = StandardMaterial3D.new()
	_dmg_band_material.albedo_color = DMG_BAND_COLOR
	_dmg_band_material.flags_unshaded = true
	_dmg_band_material.flags_transparent = true
	_dmg_band_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dmg_band_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_dmg_band_material.billboard_keep_scale = true
	_dmg_band_material.render_priority = 3  # above bar background (1) and fill (2)

	_dmg_band = MeshInstance3D.new()
	_dmg_band.name = "DamagePreviewBand"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(FILL_MAX_WIDTH, FILL_HEIGHT)
	_dmg_band.mesh = mesh
	_dmg_band.material_override = _dmg_band_material
	_dmg_band.position = Vector3(0.0, 0.0, 0.02)  # in front of the fill (0.01)
	_dmg_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dmg_band.visible = false
	add_child(_dmg_band)


## Pulse the band's alpha so incoming damage reads as urgent. Honors the global
## animations toggle: with animations off it holds a steady mid-alpha instead.
func _start_damage_blink() -> void:
	if _dmg_band_tween != null and _dmg_band_tween.is_valid():
		_dmg_band_tween.kill()
	_dmg_band_tween = null
	if _dmg_band_material == null:
		return

	if not _blink_enabled():
		var c := _dmg_band_material.albedo_color
		c.a = 0.8
		_dmg_band_material.albedo_color = c
		return

	_dmg_band_tween = create_tween()
	_dmg_band_tween.set_loops()
	_dmg_band_tween.tween_method(_set_band_alpha, 1.0, DMG_BAND_MIN_ALPHA, DMG_BAND_BLINK_TIME)
	_dmg_band_tween.tween_method(_set_band_alpha, DMG_BAND_MIN_ALPHA, 1.0, DMG_BAND_BLINK_TIME)


func _set_band_alpha(a: float) -> void:
	if _dmg_band_material == null:
		return
	var c := _dmg_band_material.albedo_color
	c.a = a
	_dmg_band_material.albedo_color = c


## True unless the player has turned animations off in GameSettings.
func _blink_enabled() -> bool:
	var gs = get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("animations_on"):
		return bool(gs.animations_on())
	return true