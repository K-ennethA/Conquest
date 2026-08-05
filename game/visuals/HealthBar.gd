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
# row is built from [method StatusVisuals.group_by_id] and shows "†3".
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

## Sentinel for _status_signature. Every real signature carries the "#" that separates its
## status half from its terrain half (see _row_signature_for), so this can never collide
## with one -- which makes the first refresh after _ready or a rebind always rebuild.
const SIGNATURE_UNSET := "<unset>"

# --- Terrain chips ------------------------------------------------------------
# The badge row also carries what the GROUND is giving the unit: a wide "±AVO+15" chip per
# affected stat while the bound unit stands on terrain that moves one (tall grass +evasion,
# fortify +defense, empowering water +attack, slippery ice -evasion). Vocabulary, mark,
# colour and wording all come from [TerrainVisuals] -- the same helper the battle card and
# the hover card read, so the number over the unit and the number on the card are one
# lookup, never two.
#
# THIS REPLACED A SEPARATE "+AVO N" TAG that hung below the bar. That tag knew about exactly
# one stat, only in the positive direction, and shared none of its wording with the panels;
# folding it into the badge row costs one fewer node, covers every stat and both directions,
# and puts "where I am standing" beside "what is on me" where the player is already looking.
#
# TERRAIN CHIPS ARE DELIBERATELY THE INVERSE OF STATUS CHIPS. A status is a COLOURED chip
# with DARK ink; terrain is a DARK PLATE with COLOURED ink, and it is drawn wider. So
# "temporary condition" and "consequence of my position" are told apart by shape and by
# figure/ground before any glyph is legible -- which is the whole point of showing them in
# one row.
const TERRAIN_CHIP_WIDTH := 0.50      # wide enough for "±AVO+15" -- pinned by the live suite
const TERRAIN_CHIP_PLATE := Color(0.09, 0.07, 0.04, 0.94)  # dark bark; the coloured ink sits ON it
const TERRAIN_GLYPH_FONT_SIZE := 44
const TERRAIN_GLYPH_PIXEL_SIZE := 0.0022
const TERRAIN_GLYPH_OUTLINE := Color(0.04, 0.03, 0.01, 0.9)

## Gap between adjacent badges in the row. Equals STATUS_PIP_SPACING - STATUS_PIP_SIZE, so a
## row of nothing but status chips lands exactly where it always did.
const BADGE_GAP := STATUS_PIP_SPACING - STATUS_PIP_SIZE

var _background_material: StandardMaterial3D
var _health_material: StandardMaterial3D

# --- Shield segment -----------------------------------------------------------
# A SILVER segment appended after the green HP fill: the damage-soak shield
# ([member Unit.shield_hp]) drawn as an EXTENSION of the health bar. Both segments are
# measured against ONE points-per-pixel scale, [method ShieldVisuals.bar_fractions] --
# so with a shield that fits inside the missing health the green fill does not move at
# all and the silver tail simply claims part of the depleted track, and with a shield
# that would overrun the bar both segments rescale together rather than overflowing the
# 1.4-wide track (which the pip row and the damage band both map fractions onto).
#
# Built LAZILY, exactly like the damage band: a unit that is never shielded pays for no
# nodes, and a zero shield renders the bar this file drew before the segment existed.
const SHIELD_COLOR := Color("aeb2c2")  # == ShieldVisuals.SILVER_WORLD (steel, map-legible)
var _shield_seg: MeshInstance3D = null
var _shield_material: StandardMaterial3D = null

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

## Parent of the pip row. Created once in _ready and then only ever has its
## children swapped, so the bar's own node layout is untouched.
var _status_root: Node3D = null

## Cheap change-detector: the statuses AND the terrain bonuses currently drawn.
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
	# The shield is NOT a stat, so health_changed never fires for it: a ward granted or
	# depleted announces on the unit's own shield_changed and nowhere else. Without this
	# the silver segment would only appear the next time HP happened to move.
	if unit != null and unit.has_signal(&"shield_changed") \
			and not unit.shield_changed.is_connected(_on_bound_shield_changed):
		unit.shield_changed.connect(_on_bound_shield_changed)
	# A new unit means a whole new status list; force the next refresh to rebuild.
	_status_signature = SIGNATURE_UNSET
	_refresh_from_unit()
	_refresh_status_pips()

func _on_bound_health_changed(_old_health: int, _new_health: int) -> void:
	_refresh_from_unit()
	# HP changing is itself a status beat: a burn/poison tick lands as damage, and
	# the condition that caused it may have just expired in the same resolution.
	_refresh_status_pips()

## The bound unit's shield changed (granted, soaked a hit, or ran out). Repaint the bar:
## the silver tail is a function of HP and shield together, so this goes through the same
## refresh HP changes do.
func _on_bound_shield_changed(_current: int) -> void:
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

	# The HP fill's share of the track is normally just `percentage` -- and with no shield
	# it is EXACTLY that, the same float this line always used. A shield is what can move
	# it, and only when current + shield would overrun the fixed track (see the shared
	# scale in ShieldVisuals.bar_fractions). `percentage` remains the fallback for a caller
	# that passes a fraction without meaningful current/maximum.
	var shield: int = ShieldVisuals.shield_of(_bound_unit)
	var fill_fraction: float = percentage
	var shield_fraction: float = 0.0
	if maximum > 0:
		var fractions: Dictionary = ShieldVisuals.bar_fractions(current, maximum, shield)
		fill_fraction = float(fractions.get("hp", percentage))
		shield_fraction = float(fractions.get("shield", 0.0))

	# Update fill width, keeping it left-aligned within the background frame
	if health_fill and health_fill.mesh:
		var mesh = health_fill.mesh as QuadMesh
		mesh.size.x = FILL_MAX_WIDTH * fill_fraction
		health_fill.position.x = (FILL_MAX_WIDTH * fill_fraction - FILL_MAX_WIDTH) * 0.5

	_apply_shield_segment(fill_fraction, shield_fraction)

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


# --- Shield segment -----------------------------------------------------------

## Draw (or hide) the silver shield tail. [param fill_fraction] is where the green fill
## ends and [param shield_fraction] is how much of the track the shield claims after it,
## both as fractions of [constant FILL_MAX_WIDTH].
##
## A zero (or sub-pixel) shield hides the segment WITHOUT building it, so an unshielded
## unit's bar is exactly the two quads it always was.
func _apply_shield_segment(fill_fraction: float, shield_fraction: float) -> void:
	if shield_fraction <= ShieldVisuals.MIN_FRACTION:
		if _shield_seg != null and is_instance_valid(_shield_seg):
			_shield_seg.visible = false
		return

	_ensure_shield_segment()
	var mesh := _shield_seg.mesh as QuadMesh
	mesh.size = Vector2(FILL_MAX_WIDTH * shield_fraction, FILL_HEIGHT)
	# Same fraction -> x mapping the fill and the damage band use: the track spans
	# [-FILL_MAX_WIDTH/2, +FILL_MAX_WIDTH/2], and this quad is CENTRED on the midpoint of
	# [fill_fraction, fill_fraction + shield_fraction] -- i.e. it starts exactly where the
	# green fill ends, which is what makes it read as one continuous bar.
	var mid: float = fill_fraction + shield_fraction * 0.5
	_shield_seg.position.x = -FILL_MAX_WIDTH * 0.5 + FILL_MAX_WIDTH * mid
	_shield_seg.visible = true


func _ensure_shield_segment() -> void:
	if _shield_seg != null and is_instance_valid(_shield_seg):
		return
	_shield_material = StandardMaterial3D.new()
	_shield_material.albedo_color = SHIELD_COLOR
	_shield_material.flags_unshaded = true
	# Opaque like the fill it continues: a translucent tail would show the dark crimson
	# "lost health" track through it and read as damage rather than as protection.
	_shield_material.flags_transparent = false
	_shield_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_shield_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_shield_material.billboard_keep_scale = true
	_shield_material.render_priority = 2  # with the fill: above the background (1)

	_shield_seg = MeshInstance3D.new()
	_shield_seg.name = "ShieldSegment"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.0, FILL_HEIGHT)
	_shield_seg.mesh = mesh
	_shield_seg.material_override = _shield_material
	_shield_seg.position = Vector3(0.0, 0.0, 0.011)  # just in front of the fill (0.01)
	_shield_seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield_seg.visible = false
	add_child(_shield_seg)


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
	# One refresh covers both halves of the row: a tile can gain or lose a passive bonus
	# between turns (grass catching fire), and the signature guard below sees that change
	# exactly as it sees a status landing.
	_refresh_status_pips()


## A status landed on / left SOME unit. Global like the other beats -- every bar wakes,
## and the signature guard makes all but the affected one an early return.
func _on_status_changed_beat(_unit, _condition) -> void:
	_refresh_status_pips()


## An action can displace a unit (knockback/pull) or alter its tile, either of which
## changes the terrain half of the row without a move beat firing for this unit.
func _on_status_action_beat(_unit, _action_type) -> void:
	_refresh_status_pips()


## GameEvents.unit_moved -- THE beat for the terrain chips. A unit can walk onto or off tall
## grass with no HP change and no status event at all, so this is what makes "±AVO+15" appear
## the instant it steps into grass and vanish when it steps out. Deliberately this signal and
## not PlayerManager's turn signals, which never fire on an AI turn (CONQUEST.md rule 2).
func _on_status_move_beat(_unit, _from_position, _to_position) -> void:
	_refresh_status_pips()


## "id:turns:count|…" for the GROUPED conditions, then "#" and "stat:amount|…" for the
## TERRAIN bonuses. Any change in which statuses are active, their order, their remaining
## turns, their stack depth, OR which stats the ground under the unit is moving and by how
## much produces a different string -- so a poison deepening from x2 to x3 rebuilds the row,
## and so does a step from bare earth into tall grass.
func _row_signature_for(groups: Array, terrain: Array) -> String:
	var parts: PackedStringArray = []
	for group in groups:
		var condition = group.get("condition", null)
		var id_text: String = "?"
		if typeof(condition) == TYPE_OBJECT and "id" in condition:
			id_text = String(condition.id)
		parts.append("%s:%d:%d" % [
			id_text, int(group.get("turns_left", 0)), int(group.get("count", 1))])
	var terrain_parts: PackedStringArray = []
	for entry in terrain:
		terrain_parts.append("%s:%d" % [
			String((entry as Dictionary).get("stat", "")),
			int((entry as Dictionary).get("amount", 0))])
	return "%s#%s" % ["|".join(parts), "|".join(terrain_parts)]


## Rebuild the badge row: the TERRAIN chips the ground is granting, then the unit's active
## conditions -- but only when either list actually changed. Nothing on the unit and plain
## ground under it leaves the row empty, which is exactly today's appearance.
##
## Terrain first (leftmost), and in the same order the battle card and the hover card use:
## where a unit is standing is the fact that changes every time it moves, so it holds the
## same slot on every surface instead of shuffling behind whatever conditions it has.
func _refresh_status_pips() -> void:
	if _status_root == null or not is_instance_valid(_status_root):
		return

	# Null-safe all the way down: a freed unit, a unit with no controller, or an
	# empty list all come back as an empty array. Grouped by id so severity renders
	# as one badge, not N identical ones.
	var groups: Array = StatusVisuals.group_by_id(
		StatusVisuals.active_conditions(_bound_unit))
	# Terrain, from the shared helper -- the SAME numbers the panels quote and the same ones
	# MoveContext.hit_chance rolls against, never a second derivation.
	var board = CombatServices.board() if CombatServices else null
	var terrain: Array = TerrainVisuals.bonuses_for(_bound_unit, board)

	var signature: String = _row_signature_for(groups, terrain)
	if signature == _status_signature:
		return
	_status_signature = signature

	for child in _status_root.get_children():
		child.queue_free()

	# Cap each half: past its budget the last slot becomes a neutral overflow marker, so
	# neither a heavily-afflicted unit nor a freak stack of terrain layers can grow an
	# unbounded ribbon of badges.
	var terrain_shown: int = TerrainVisuals.shown_count(terrain.size())
	var terrain_hidden: int = TerrainVisuals.hidden_count(terrain.size())
	var total: int = groups.size()
	var shown: int = StatusVisuals.shown_count(total)
	var hidden: int = StatusVisuals.hidden_count(total)

	# Lay the row out by MEASURED WIDTH rather than a fixed step: terrain chips are wider
	# than status pips, so a uniform spacing would either overlap them or scatter the pips.
	# With no terrain chips the arithmetic reduces to the old (i - (n-1)/2) * spacing exactly,
	# because BADGE_GAP is defined as STATUS_PIP_SPACING - STATUS_PIP_SIZE.
	var widths: Array[float] = []
	for i in range(terrain_shown):
		widths.append(TERRAIN_CHIP_WIDTH)
	if terrain_hidden > 0:
		widths.append(STATUS_PIP_SIZE)
	for i in range(shown):
		widths.append(STATUS_PIP_SIZE)
	if hidden > 0:
		widths.append(STATUS_PIP_SIZE)
	if widths.is_empty():
		return

	var span: float = 0.0
	for w in widths:
		span += w
	span += BADGE_GAP * float(widths.size() - 1)

	# Walk left to right from the centred left edge, advancing by each slot's own width.
	var cursor: float = -span * 0.5
	var slot: int = 0
	for i in range(terrain_shown):
		var entry: Dictionary = terrain[i]
		var cx: float = cursor + widths[slot] * 0.5
		var plate := _make_chip(TERRAIN_CHIP_PLATE, cx, TERRAIN_CHIP_WIDTH)
		plate.name = "TerrainChip"
		_status_root.add_child(plate)
		_status_root.add_child(_make_terrain_glyph(
			TerrainVisuals.chip_text(entry), cx, TerrainVisuals.color_for(entry)))
		cursor += widths[slot] + BADGE_GAP
		slot += 1
	if terrain_hidden > 0:
		var tx: float = cursor + widths[slot] * 0.5
		_status_root.add_child(_make_chip(TERRAIN_CHIP_PLATE, tx, STATUS_PIP_SIZE))
		_status_root.add_child(_make_terrain_glyph(
			TerrainVisuals.overflow_label(terrain_hidden), tx, TerrainVisuals.GAIN_COLOR))
		cursor += widths[slot] + BADGE_GAP
		slot += 1

	for i in range(shown):
		var group: Dictionary = groups[i]
		var condition = group.get("condition", null)
		var info: Dictionary = StatusVisuals.info_for(condition)
		var color: Color = info.get("color", StatusVisuals.OVERFLOW_COLOR)
		var x: float = cursor + widths[slot] * 0.5
		_status_root.add_child(_make_status_pip(color, x))
		var glyph: String = StatusVisuals.glyph_for(condition)
		var count: int = int(group.get("count", 1))
		if count > 1:
			glyph += str(count)
		_status_root.add_child(_make_status_glyph(glyph, x))
		cursor += widths[slot] + BADGE_GAP
		slot += 1
	if hidden > 0:
		var overflow_x: float = cursor + widths[slot] * 0.5
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


## One SQUARE status chip quad tinted [param color], placed at [param x].
func _make_status_pip(color: Color, x: float) -> MeshInstance3D:
	return _make_chip(color, x, STATUS_PIP_SIZE)


## One chip quad [param width] wide (and always [constant STATUS_PIP_SIZE] tall, so the row
## has one baseline), tinted [param color] and centred on [param x] in the row's local space.
func _make_chip(color: Color, x: float, width: float) -> MeshInstance3D:
	var pip := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(width, STATUS_PIP_SIZE)
	pip.mesh = mesh
	pip.position = Vector3(x, 0.0, 0.0)

	# Same billboard recipe as the bar itself (unshaded + BILLBOARD_ENABLED +
	# keep_scale), so the pips face the camera and hold a constant on-screen size
	# exactly like the bar they sit on.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.flags_unshaded = true
	# The terrain plate is nearly-but-not-quite opaque, so it has to be allowed to blend.
	mat.flags_transparent = color.a < 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 \
		else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.render_priority = 3  # above the bar's background (1) and fill (2)
	pip.material_override = mat
	return pip


## The terrain chip's label ("±AVO+15"), drawn in the TERRAIN colour on the dark plate --
## the deliberate inverse of a status badge's dark ink on a coloured chip, so the two kinds
## of badge are told apart by figure/ground before either is read. Smaller pixel size than a
## status glyph because it carries seven characters rather than one or two; the live suite
## pins that the plate is wider than the string it has to draw.
func _make_terrain_glyph(text: String, x: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = "TerrainChipLabel"
	label.text = text
	label.position = Vector3(x, 0.0, 0.01)  # just in front of the plate quad
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# NOTE: fixed_size stays OFF -- with it on, pixel_size * font_size stops mapping to world
	# units and the label renders screen-huge (the "+AVO 15 plastered across the whole map"
	# bug the retired tag recorded).
	label.font_size = TERRAIN_GLYPH_FONT_SIZE
	label.pixel_size = TERRAIN_GLYPH_PIXEL_SIZE
	label.modulate = color
	label.outline_modulate = TERRAIN_GLYPH_OUTLINE
	label.outline_size = 5
	label.render_priority = 5   # above bar bg (1), fill (2), chips (3)
	label.outline_render_priority = 4
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label


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
	# slice between where HP will land and where it is now. Measured against the SAME
	# denominator the fill and the shield tail use, so the band still lands on the HP it
	# describes when a big shield has rescaled the track (identical to `mx` with no shield).
	var denom: float = float(
		ShieldVisuals.denominator(cur, mx, ShieldVisuals.shield_of(_bound_unit)))
	var cur_frac: float = clampf(float(cur) / denom, 0.0, 1.0)
	var rem_frac: float = clampf(float(cur - amount) / denom, 0.0, cur_frac)
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