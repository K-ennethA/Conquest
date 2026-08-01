extends TileObject

class_name Unit

# Unit stats component integration
@export var stats_resource: UnitStatsResource
@onready var unit_stats: UnitStats = get_node_or_null("UnitStats")

# Optional custom-character data (identity + base stats + moveset). When present,
# this unit can perform data-authored moves via the combat model (MoveExecutor).
@export var character_resource: CharacterResource

## Optional reward this unit grants to WHOEVER lands the killing blow. When set and
## this unit dies with a known, still-valid last attacker, that attacker receives a
## fresh copy of this [StatusCondition] through its own StatusController (see
## [method _grant_kill_reward]). Null (the default) = no reward, so every existing
## unit behaves exactly as before. Generic -- any unit can carry one -- but authored
## on the neutral camp creature in the Arena (ArenaRoundBuilder sets it at spawn).
@export var kill_reward: StatusCondition

## The last unit to deal damage to this one, tracked off GameEvents.damage_dealt so a
## kill_reward can credit the killer. Always re-checked with is_instance_valid before
## use, since the attacker may have been freed between the hit and this unit's death.
var _last_damager: Unit = null

@export var has_turn: bool = false

# Player ownership
var owner_player: Player = null
var has_acted_this_turn: bool = false
## Set once the unit has moved this turn. A unit may move only once per turn
## unless an ability or move effect grants extra movement (see [method grant_extra_move]).
var has_moved_this_turn: bool = false

# --- AI behavior (resolved at spawn) ----------------------------------------
# WHERE this unit was placed and HOW it should fight. The spawner (MapLoader at
# load, SpawnManager for scheduled/endless waves) calls configure_ai_behavior()
# once, resolving the spawn point's authored override against the character
# default. Until configured, the getters fall back to the CharacterResource
# defaults, so a unit spawned outside the map loader (e.g. in a test) still has a
# sane stance. Bot/BossController read these every turn.
var home_cell: Vector2i = Vector2i(-1, -1)
var _ai_configured: bool = false
var _ai_stance: String = ""
var _aggro_range: int = -1
var _leash_radius: int = -1

# Signals
signal unit_died(unit: Unit)
signal unit_action_completed(unit: Unit, action_type: String)
signal owner_changed(unit: Unit, old_owner: Player, new_owner: Player)
## Temporary damage-soak shield changed (0 when depleted). Drives any shield HUD.
signal shield_changed(current: int)

## Temporary HP shield that absorbs incoming damage before real health (see
## take_damage / grant_shield). 0 = none. Granted by e.g. Crystalline Ward.
var shield_hp: int = 0

# Inspector testing properties (for runtime testing)
@export_group("Runtime Testing")
@export var test_damage_amount: int = 10:
	set(value):
		if value > 0 and is_inside_tree():
			take_damage(value)
			test_damage_amount = 0  # Reset after use

@export var test_heal_amount: int = 10:
	set(value):
		if value > 0 and is_inside_tree():
			heal(value)
			test_heal_amount = 0  # Reset after use

@export var current_health_display: int:
	get:
		return current_health
	set(value):
		if unit_stats and value >= 0:
			unit_stats.set_stat("health", min(value, max_health))

# Visual management
var visual_manager: UnitVisualManager
var player_assignment: PlayerMaterials.PlayerTeam = PlayerMaterials.PlayerTeam.NEUTRAL

# Health management
var current_health: int:
	get:
		if unit_stats:
			return unit_stats.get_stat("health")
		return 0

var max_health: int:
	get:
		if unit_stats:
			return unit_stats.get_base_stat("health")
		return 0

# Visual feedback
var _mesh_instance: MeshInstance3D
var _original_material: Material

# Board footprint. Cells are 2 world units across (see Grid.cell_size); the mesh
# scale a large unit was built from is cached the first time apply_footprint_visual()
# runs so re-applying it never multiplies the scale again.
const CELL_SIZE: float = 2.0
var _footprint_base_scale: Vector3 = Vector3.ONE
var _has_footprint_base_scale: bool = false

# --- Facing -----------------------------------------------------------------
# The model root's Y rotation is the authored correction (character_resource.model_yaw_deg)
# COMPOSED ADDITIVELY with `facing_yaw`, the WORLD direction the unit should face. The
# authored correction's job is to align the sculpt's front to Godot's -Z, so with it
# applied the model is canonical (faces world -Z); `facing_yaw` then rotates that canonical
# forward. facing_yaw 0 = world -Z (north / up-board / AWAY from the south-side camera);
# facing_yaw = PI = world +Z (south / down-board / TOWARD the camera). The spawner sets it
# so a unit faces the opposing side; face_cell/face_direction update it at runtime so a
# unit turns toward what it acts on. The authored correction is NEVER overwritten -- the
# final model yaw is always model_yaw_deg + facing_yaw.
var facing_yaw: float = 0.0

# Death guard: death resolution (signals + despawn) must run exactly once, no
# matter how many code paths observe HP hitting 0 (take_damage, the health_changed
# signal, or a heal-then-lethal edge). Latches true on the first death.
var _is_dead: bool = false

func _ready() -> void:
	_setup_stats_component()
	_setup_visuals()
	_connect_events()
	_setup_visual_management()

func _setup_visual_management() -> void:
	"""Set up visual management for this unit"""
	# Find or create visual manager
	visual_manager = _find_visual_manager()
	if not visual_manager:
		# No visual manager (e.g. headless / test harness). Visuals are cosmetic; skip silently.
		return
	
	# Check if we have an owner player (new system)
	if owner_player:
		visual_manager.setup_unit_visuals_for_player(self, owner_player)
	else:
		# Fallback to old system - determine player assignment from scene tree
		player_assignment = _determine_player_from_scene_tree()
		visual_manager.setup_unit_visuals(self, player_assignment)

func _find_visual_manager() -> UnitVisualManager:
	"""Find UnitVisualManager in the scene tree"""
	# Look for it in the scene root or map
	var scene_root = get_tree().current_scene
	if scene_root:
		var manager = scene_root.find_child("UnitVisualManager", true, false)
		if manager:
			return manager

		# If not found, create one under the current scene
		var new_manager = UnitVisualManager.new()
		new_manager.name = "UnitVisualManager"
		scene_root.add_child(new_manager)
		return new_manager

	# No current scene (e.g. running headless / under a test harness). Skip
	# visual manager creation rather than dereferencing a null scene root.
	return null

func _determine_player_from_scene_tree() -> PlayerMaterials.PlayerTeam:
	"""Determine player assignment based on parent node names"""
	var parent = get_parent()
	while parent:
		if parent.name.to_lower().contains("player1"):
			return PlayerMaterials.PlayerTeam.PLAYER_1
		elif parent.name.to_lower().contains("player2"):
			return PlayerMaterials.PlayerTeam.PLAYER_2
		parent = parent.get_parent()
	
	return PlayerMaterials.PlayerTeam.NEUTRAL

func _setup_stats_component() -> void:
	"""Initialize the UnitStats component"""
	# Create UnitStats component if it doesn't exist
	if not unit_stats:
		unit_stats = UnitStats.new()
		unit_stats.name = "UnitStats"

		# Decide which UnitStatsResource drives the runtime stats. When a
		# CharacterResource is assigned it is the canonical authoring data
		# (D1): derive a UnitStatsResource from its base stats and feed the
		# existing UnitStats component. A character always wins over any
		# pre-assigned stats_resource. With no character, behaviour is
		# unchanged from the legacy stats_resource-only path.
		var effective_resource: UnitStatsResource = stats_resource
		if character_resource:
			effective_resource = _build_stats_resource_from_character(character_resource)

		# Set up stats resource BEFORE adding to tree
		if effective_resource:
			unit_stats.stats_resource = effective_resource
		else:
			push_error("Unit requires a UnitStatsResource! Please assign one in the inspector.")
			return

		# Now add to tree, _ready() will work properly
		add_child(unit_stats)

	# Connect to stats events
	if unit_stats:
		unit_stats.health_changed.connect(_on_health_changed)
		unit_stats.stat_changed.connect(_on_stat_changed)

	# A character-backed unit also gets its combat companion components
	# (moveset cooldown tracking + status conditions).
	if character_resource:
		_setup_character_components()


## Build a runtime [UnitStatsResource] from a [CharacterResource]'s authoring
## data. The character owns the base stat block (D1); the derived resource is
## what the [UnitStats] component consumes, so take_damage/heal/get_stat keep
## working unchanged. Note: CharacterResource.base_magic_defense has no
## counterpart on UnitStatsResource and is intentionally not mapped.
func _build_stats_resource_from_character(character: CharacterResource) -> UnitStatsResource:
	var derived := UnitStatsResource.new()
	derived.unit_name = character.display_name
	derived.unit_type = String(character.character_id)
	derived.max_health = character.base_health
	derived.base_attack = character.base_attack
	derived.base_defense = character.base_defense
	derived.base_magic = character.base_magic
	derived.base_speed = character.base_speed
	derived.movement_range = character.base_movement
	derived.attack_range = character.attack_range
	return derived


## Attach the combat companion components a character-backed unit needs, once.
## Both are guarded so repeated setup calls never duplicate them.
func _setup_character_components() -> void:
	# Moveset cooldown / uses tracker. The controller tracks state lazily by
	# move_id and needs no explicit seeding; if a sibling task adds a seeding
	# hook, feed it the character's moveset via duck-typing.
	if not has_node("MovesetController"):
		var moveset_controller := MovesetController.new()
		moveset_controller.name = "MovesetController"
		if moveset_controller.has_method("seed_from_moveset"):
			moveset_controller.call("seed_from_moveset", character_resource.moveset)
		add_child(moveset_controller)

	# Active status-condition tracker.
	if not has_node("StatusController"):
		var status_controller := StatusController.new()
		status_controller.name = "StatusController"
		status_controller.owner_unit = self
		add_child(status_controller)

	# Character abilities (always-on / triggered passives). Attached as a CHILD
	# so AbilitySystem._unit() resolves to this unit naturally, and only when the
	# character actually declares abilities -- a character with none keeps the
	# exact node layout it had before.
	if not has_node("AbilitySystem") and not character_resource.abilities.is_empty():
		var ability_system := AbilitySystem.new()
		ability_system.name = "AbilitySystem"
		ability_system.owner_unit = self
		for ability in character_resource.abilities:
			ability_system.add_ability(ability)
		add_child(ability_system)

func _setup_visuals() -> void:
	"""Initialize visual components"""
	# Only set up visuals if MeshInstance3D exists (for testing compatibility)
	if has_node("MeshInstance3D"):
		_mesh_instance = get_node("MeshInstance3D")
		if _mesh_instance and _mesh_instance.mesh and _mesh_instance.mesh.material:
			_original_material = _mesh_instance.mesh.material
		# Size the model to the unit's footprint even when no visual manager is
		# present (headless / test harness). No-op for normal 1x1 units.
		apply_footprint_visual()
	# Swap in the character's authored model, if it has one.
	_setup_character_model()


## Instantiate the character's authored model (a Blender export -- see
## tools/blender/prepare_unit.py) in place of the placeholder capsule.
##
## Models are exported origin-at-feet and already scaled to their real height, so
## they need no runtime correction: dropping one in at the unit's origin puts its
## feet on the tile. The capsule is HIDDEN rather than removed, because
## UnitVisualManager still drives team colour/selection through it and other code
## looks it up by name.
func _setup_character_model() -> void:
	if character_resource == null or character_resource.model_scene == null:
		return
	if get_node_or_null("CharacterModel") != null:
		return  # already built

	var model := character_resource.model_scene.instantiate()
	if model == null:
		push_warning("[Unit] model_scene failed to instantiate for %s" % name)
		return
	model.name = "CharacterModel"
	add_child(model)

	# Centre a multi-cell model over its whole footprint, exactly like the capsule,
	# then apply the character's authored yaw (a sculpt that faces the wrong way) and
	# scale (a small creature). Scale is about the feet-at-origin so it stays grounded.
	if model is Node3D:
		var m := model as Node3D
		m.position = get_footprint_offset()
		var yaw: float = character_resource.model_yaw_deg if "model_yaw_deg" in character_resource else 0.0
		var model_scale: float = character_resource.model_scale if "model_scale" in character_resource else 1.0
		# Compose the authored correction with the spawn/runtime facing (see the facing_yaw
		# note above). The spawner sets facing_yaw BEFORE this node enters the tree, so the
		# model is built already oriented toward the opposing side.
		m.rotation = Vector3(0.0, deg_to_rad(yaw) + facing_yaw, 0.0)
		m.scale = Vector3.ONE * maxf(0.05, model_scale)

	if _mesh_instance:
		_mesh_instance.visible = false


# --- Facing API -------------------------------------------------------------

## Decide the world-facing yaw (RADIANS) a freshly spawned unit takes so it faces the
## OPPOSING side, to be composed with the authored model_yaw_deg. PURE + STATIC so the
## decision is unit-testable. Convention: 0 = world -Z (north / up-board), PI = world +Z
## (south / down-board / toward the south-side camera). A unit in the TOP (north) half
## faces down-board (+Z, PI); one in the BOTTOM (south) half faces up-board (-Z, 0).
## Exactly on the midline it faces the majority side of [param enemy_rows]; with no
## decisive enemy it faces south (PI, toward the camera).
static func spawn_facing_yaw(spawn_row: int, map_height: int, enemy_rows: Array = []) -> float:
	var midline: float = float(maxi(1, map_height) - 1) * 0.5
	if float(spawn_row) < midline:
		return PI
	if float(spawn_row) > midline:
		return 0.0
	# Dead-center on the midline: face the majority of enemy spawns, else south.
	var below: int = 0
	var above: int = 0
	for r in enemy_rows:
		var rr: int = int(r)
		if rr > spawn_row:
			below += 1
		elif rr < spawn_row:
			above += 1
	if below > above:
		return PI
	if above > below:
		return 0.0
	return PI

## World-facing yaw (RADIANS) whose canonical forward points along the world direction
## ([param dx], [param dz]). With the authored correction applied the model faces -Z, and
## rotate(-Z, yaw) = (-sin yaw, -cos yaw), so solving for the target direction gives this.
## Convention-independent: only the sign of the delta matters, so grid-space or world-space
## deltas both yield the same angle.
static func facing_yaw_for_delta(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)

## Set the world-facing yaw (radians) and re-apply the composed model rotation. Never
## touches the authored model_yaw_deg -- the two are summed in [method _apply_model_facing].
func set_facing_yaw(yaw_rad: float) -> void:
	facing_yaw = yaw_rad
	_apply_model_facing()

## Compose and apply the model root's Y rotation = deg_to_rad(model_yaw_deg) + facing_yaw.
## No-op when there is no character model (placeholder / headless units).
func _apply_model_facing() -> void:
	var m := get_node_or_null("CharacterModel") as Node3D
	if m == null:
		return
	m.rotation = Vector3(0.0, deg_to_rad(_authored_model_yaw()) + facing_yaw, 0.0)

## The authored per-model yaw correction in degrees (0 when there is no character or the
## field is absent).
func _authored_model_yaw() -> float:
	if character_resource != null and "model_yaw_deg" in character_resource:
		return character_resource.model_yaw_deg
	return 0.0

## Turn the model to face world direction ([param dx], [param dz]) -- used to face along a
## just-completed move. No-op for a zero direction, a missing model, or a MULTI-TILE boss
## (footprint != 1x1), whose centered model reads wrong when spun to an arbitrary angle.
func face_direction(dx: float, dz: float) -> void:
	if absf(dx) < 0.0001 and absf(dz) < 0.0001:
		return
	if get_footprint() != Vector2i.ONE:
		return
	_turn_model_to(facing_yaw_for_delta(dx, dz))

## Turn the model to face [param target_cell] -- used to face the target of an action.
## Faces from the unit's CURRENT world position toward the cell center, so calling it with
## the unit's own cell is a harmless no-op. Same boss / missing-model guards as
## [method face_direction] (via the delegation to it).
func face_cell(target_cell: Vector2i) -> void:
	var here: Vector3 = global_position if is_inside_tree() else position
	var target_x: float = float(target_cell.x) * CELL_SIZE + CELL_SIZE * 0.5
	var target_z: float = float(target_cell.y) * CELL_SIZE + CELL_SIZE * 0.5
	face_direction(target_x - here.x, target_z - here.z)

## Rotate the model root to [param target_facing_yaw] (world-facing, radians), composed with
## the authored correction. A quick eased turn when animations are on and we are in the tree;
## an instant set otherwise. Shortest-path via lerp_angle so it never spins the long way
## around the +/-PI wrap. Records facing_yaw so the state stays authoritative.
func _turn_model_to(target_facing_yaw: float) -> void:
	var m := get_node_or_null("CharacterModel") as Node3D
	if m == null:
		# No model yet: still record the intent so a later build/apply uses it.
		facing_yaw = target_facing_yaw
		return
	var target_rot: float = deg_to_rad(_authored_model_yaw()) + target_facing_yaw
	facing_yaw = target_facing_yaw
	var dur: float = 0.0
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null and GameSettings.has_method("scaled_time"):
		dur = GameSettings.scaled_time(0.1)
	if dur <= 0.0 or not is_inside_tree():
		m.rotation = Vector3(0.0, target_rot, 0.0)
		return
	var start_rot: float = m.rotation.y
	var apply := func(t: float) -> void:
		m.rotation.y = lerp_angle(start_rot, target_rot, t)
	var tw := create_tween()
	tw.tween_method(apply, 0.0, 1.0, dur)

func _connect_events() -> void:
	"""Connect to game events"""
	# Only connect if GameEvents exists (for testing compatibility)
	if GameEvents:
		GameEvents.unit_selected.connect(_on_unit_selected)
		GameEvents.unit_deselected.connect(_on_unit_deselected)
		# Track who last hit us, so a kill_reward can credit the killer on death.
		if GameEvents.has_signal("damage_dealt") \
				and not GameEvents.damage_dealt.is_connected(_on_any_damage_dealt):
			GameEvents.damage_dealt.connect(_on_any_damage_dealt)

# Stat access methods (preferred interface)
func get_stat(stat_name: String) -> int:
	"""Get current stat value"""
	if unit_stats:
		return unit_stats.get_stat(stat_name)
	return 0

func get_base_stat(stat_name: String) -> int:
	"""Get base stat value (without modifiers)"""
	if unit_stats:
		return unit_stats.get_base_stat(stat_name)
	return 0

func modify_stat(stat_name: String, amount: int, is_permanent: bool = false) -> void:
	"""Modify a stat by amount"""
	if unit_stats:
		unit_stats.modify_stat(stat_name, amount, is_permanent)

func set_stat(stat_name: String, value: int, is_permanent: bool = false) -> void:
	"""Set a stat to specific value"""
	if unit_stats:
		unit_stats.set_stat(stat_name, value, is_permanent)

func add_stat_modifier(stat_name: String, amount: int, duration: int = -1) -> int:
	"""Add temporary stat modifier"""
	if unit_stats:
		return unit_stats.add_stat_modifier(stat_name, amount, duration)
	return -1

func remove_stat_modifier(modifier_id: int) -> bool:
	"""Remove specific stat modifier"""
	if unit_stats:
		return unit_stats.remove_stat_modifier(modifier_id)
	return false

# Health management
func take_damage(amount: int) -> void:
	"""Apply damage to the unit"""
	# A dormant neutral camp wakes the instant it is hit -- from now on the bot AI fights
	# for it (attacks the nearest hostile of either side).
	if amount > 0 and is_dormant() and not provoked:
		provoked = true
	# A temporary shield (e.g. Gem Knight's Crystalline Ward) soaks incoming damage
	# before any of it reaches real health. Absorb up to what the shield holds, then
	# let the remainder fall through to HP below.
	if amount > 0 and shield_hp > 0:
		var absorbed: int = mini(shield_hp, amount)
		shield_hp = maxi(0, shield_hp - absorbed)
		amount -= absorbed
		shield_changed.emit(shield_hp)
	if amount <= 0:
		return
	if unit_stats:
		var current_hp = unit_stats.get_stat("health")
		var new_hp = max(0, current_hp - amount)
		unit_stats.set_stat("health", new_hp)

		if new_hp <= 0:
			_on_unit_died()


## Grant a temporary damage-soaking shield. Refreshes to the strongest value rather
## than stacking (a 15 shield re-granted stays 15, never 30) -- the same "reductions
## refresh, never compound" rule the damage-reduction statuses follow.
func grant_shield(amount: int) -> void:
	if amount <= 0:
		return
	shield_hp = maxi(shield_hp, amount)
	shield_changed.emit(shield_hp)


## Current shield points remaining (0 when none).
func get_shield() -> int:
	return shield_hp

func heal(amount: int) -> void:
	"""Heal the unit"""
	if unit_stats:
		var current_hp = unit_stats.get_stat("health")
		var max_hp = unit_stats.get_base_stat("health")
		var new_hp = min(max_hp, current_hp + amount)
		unit_stats.set_stat("health", new_hp)

func is_alive() -> bool:
	"""Check if unit is alive"""
	return not _is_dead and current_health > 0

func is_at_full_health() -> bool:
	"""Check if unit is at full health"""
	return current_health >= max_health

# Unit type and properties
func get_unit_type() -> String:
	"""Get the unit's type"""
	if unit_stats and unit_stats.stats_resource:
		return unit_stats.stats_resource.unit_type
	return ""

func get_display_name() -> String:
	"""Get the unit's display name"""
	if unit_stats and unit_stats.stats_resource:
		return unit_stats.stats_resource.unit_name
	return "Unknown Unit"

func is_ranged_unit() -> bool:
	"""Check if this is a ranged unit"""
	if unit_stats and unit_stats.stats_resource:
		return unit_stats.stats_resource.is_ranged_unit()
	return false

# Player ownership methods
func set_owner_player(player: Player) -> void:
	"""Set the player who owns this unit"""
	var old_owner = owner_player
	owner_player = player
	
	# Update visual identification
	if player:
		player_assignment = _get_player_assignment_from_player(player)
		# Update visuals immediately if visual manager exists
		if visual_manager:
			visual_manager.setup_unit_visuals_for_player(self, player)
	else:
		player_assignment = PlayerMaterials.PlayerTeam.NEUTRAL
		# Update visuals to neutral
		if visual_manager:
			visual_manager.setup_unit_visuals(self, player_assignment)
	
	owner_changed.emit(self, old_owner, player)

func get_owner_player() -> Player:
	"""Get the player who owns this unit"""
	return owner_player

## Faction id for win-condition scoring (see [WinCondition]): the owning player's
## slot, or -1 for an unowned/neutral unit. Lets DefeatBoss / DefeatAllEnemies tell
## friend from foe on live units without knowing about the Player type.
func get_team() -> int:
	return owner_player.player_id if owner_player != null else -1

func _get_player_assignment_from_player(player: Player) -> PlayerMaterials.PlayerTeam:
	"""Convert Player to PlayerMaterials.PlayerTeam enum"""
	if not player:
		return PlayerMaterials.PlayerTeam.NEUTRAL
	
	match player.player_id:
		0:
			return PlayerMaterials.PlayerTeam.PLAYER_1
		1:
			return PlayerMaterials.PlayerTeam.PLAYER_2
		_:
			return PlayerMaterials.PlayerTeam.NEUTRAL

# Turn action management

## Extra ACTIONS beyond the first this unit may take each turn (Arena "act twice"
## augments grant this; 0 for every normal unit, so nothing else changes behaviour).
## Consumed at mark_action_completed: while the unit still has budget this turn it does
## NOT latch "done" and its move is refreshed, so the player/AI can command it again.
var arena_extra_actions: int = 0
## Actions already completed this turn, compared against arena_extra_actions.
var _actions_taken_this_turn: int = 0

func reset_turn_actions() -> void:
	"""Reset unit's actions for a new turn"""
	has_acted_this_turn = false
	has_moved_this_turn = false
	_actions_taken_this_turn = 0

func mark_action_completed(action_type: String) -> void:
	"""Mark that this unit has completed an action. Normally this ends its turn, but a
	unit granted extra actions (arena_extra_actions) stays actable until its budget for
	the turn is spent -- each extra action also refreshes its move, so it is a full
	additional action, not just a second attack from the same spot."""
	_actions_taken_this_turn += 1
	if _actions_taken_this_turn <= maxi(0, arena_extra_actions):
		# Budget remains: grant another full action this turn instead of latching done.
		has_moved_this_turn = false
	else:
		has_acted_this_turn = true
	unit_action_completed.emit(self, action_type)

func mark_moved() -> void:
	"""Mark that this unit has used its move for the turn (does NOT end its turn;
	the unit can still take an action). Moving again is blocked until reset or an
	extra-move grant."""
	has_moved_this_turn = true

func grant_extra_move() -> void:
	"""Allow the unit to move again this turn (for abilities / move effects)."""
	has_moved_this_turn = false

func can_act() -> bool:
	"""Check if unit can still take its action this turn"""
	return not has_acted_this_turn and is_alive()

func can_move() -> bool:
	"""Check if unit can move this turn (once, unless granted extra movement, and
	never while an active status roots the unit in place)"""
	return is_alive() and not has_acted_this_turn and not has_moved_this_turn \
		and not is_immobilized()

## True if any active [StatusCondition] on this unit sets [param flag_name] in its
## rule_flags. Null-safe: a unit with no StatusController (legacy / non-character
## units) never carries a flag, so every caller degrades to today's behaviour.
func has_status_rule_flag(flag_name: StringName) -> bool:
	# Deliberately untyped: get_status_controller() is declared -> Node, and calling
	# has_rule_flag() on a Node-typed variable would not compile.
	var controller = get_status_controller()
	if controller == null or not controller.has_method("has_rule_flag"):
		return false
	return bool(controller.has_rule_flag(flag_name))

## How many live instances of [param condition_id] this unit carries — the
## SEVERITY of a stacking condition (Poisoned x3), 0 when it has none. Null-safe
## in the same way as [method has_status_rule_flag]: a unit with no
## StatusController simply carries nothing.
func status_stack_count(condition_id: StringName) -> int:
	# Deliberately untyped, for the same reason as has_status_rule_flag above.
	var controller = get_status_controller()
	if controller == null or not controller.has_method("stack_count"):
		return 0
	return int(controller.stack_count(condition_id))

## True while a status roots this unit in place (Ensnared, Ingrained, …). The one
## place the "immobilized" flag name is spelled for movement purposes.
func is_immobilized() -> bool:
	return has_status_rule_flag(&"immobilized")

## True while a status makes this unit skip its next turn (Flinched). The one place
## the "stunned" flag name is spelled for turn-flow purposes.
##
## NOTE this is the LIVE flag, not "is being skipped right now". A 1-turn stun is
## expired by the very tick that opens the unit's turn, so the turn systems latch
## the answer at the top of the turn instead of re-asking mid-turn — ask
## [method TurnSystemBase.is_turn_skipped] for that. This accessor is for UI and
## for anything wanting to know the status is present.
func is_stunned() -> bool:
	return has_status_rule_flag(&"stunned")

## True while a status makes this unit take no damage at all (Guarded). The one
## place the "invulnerable" flag name is spelled; [DamageEffect] short-circuits on it.
func is_invulnerable() -> bool:
	return has_status_rule_flag(&"invulnerable")

## Set true for the duration of a single forced-control action while the turn system
## puppeteers this unit. Because the 1-turn Enthralled status is EXPIRED by the tick
## that opens the unit's turn (the anti-lockout mechanism), the "controlled" rule flag
## is already gone by the time the deferred forced-drive resolves its move -- so this
## transient marker carries the control state through that one action, keeping
## [method is_controlled] true so both the AI allegiance inversion and the gather-target
## inversion ([MoveContext]) treat the unit as hijacked while it strikes its own ally.
var _forced_control_action: bool = false

## Turn the transient forced-control marker on/off around a puppeteered action.
func set_forced_control(active: bool) -> void:
	_forced_control_action = active

## True while a status (Enthralled) has hijacked this unit, OR while the turn system is
## mid-way through force-driving it -- on its turn it is forced to turn on one of its OWN
## allies. The one place the "controlled" flag name is spelled. Mirror of
## [method is_stunned] / [method is_immobilized]: the turn systems LATCH this at turn
## start (before statuses tick) so a 1-turn control lasts exactly one turn and can never
## lock the unit out -- ask [method TurnSystemBase.is_turn_forced_control] for "is being
## puppeteered this turn". This accessor drives UI, the AI allegiance inversion
## ([BotController]), and the gather-target inversion ([MoveContext]).
func is_controlled() -> bool:
	return _forced_control_action or has_status_rule_flag(&"controlled")

## Damage-reduction aggregate contributed by this unit's active statuses (Braced) --
## the single most-protective [member StatusCondition.damage_taken_scale] in force, or
## 1.0 when none. Delegates to the [StatusController]; null-safe for units without one.
## [DamageEffect] reads this to combine the status reduction with the passive one.
func status_damage_taken_scale() -> float:
	var controller = get_status_controller()
	if controller == null or not controller.has_method("status_damage_taken_scale"):
		return 1.0
	return float(controller.status_damage_taken_scale())

# Validation methods
func can_be_selected_by_player(player: Player) -> bool:
	"""Check if a specific player can select this unit"""
	return owner_player == player

func can_be_controlled_by_player(player: Player) -> bool:
	"""Check if a specific player can control this unit"""
	return owner_player == player and can_act()

# Character / move system integration
func has_character() -> bool:
	"""True if this unit is backed by a CharacterResource (custom moveset)."""
	return character_resource != null

## This unit's elemental TYPE for matchup effectiveness (see [ElementChart]). Reads
## the backing [CharacterResource]; &"" (NEUTRAL) for a unit with no character or none
## authored. This is the single accessor [ElementChart.element_of] duck-types against.
func get_element() -> StringName:
	if character_resource != null:
		var e = character_resource.get("element")
		if e != null:
			return StringName(e)
	return &""

## Current health of the unit (0 when no stats component is present).
func get_hp() -> int:
	return current_health

## How many board cells this unit spans. Vector2i.ONE (a normal 1x1 unit) for
## anything without a character resource or with an invalid authored value; the
## unit's anchor cell (BoardAdapter.cell_of) is the minimum corner of that span.
## This is the ONE place other systems ask a unit about its size.
func get_footprint() -> Vector2i:
	if character_resource == null:
		return Vector2i.ONE
	if character_resource.has_method("get_footprint"):
		return character_resource.get_footprint()
	var fp = character_resource.get("footprint")
	if fp is Vector2i:
		return Vector2i(maxi(1, fp.x), maxi(1, fp.y))
	return Vector2i.ONE

## Offset from the anchor cell's center to the center of the whole footprint.
## Cells are CELL_SIZE world units across and the unit node sits at its anchor
## cell's center, so a (w,h) span reaches (w-1) cells along +X and (h-1) along +Z.
## Vector3.ZERO for a 1x1 unit.
func get_footprint_offset() -> Vector3:
	var fp := get_footprint()
	return Vector3(
		float(fp.x - 1) * CELL_SIZE * 0.5,
		0.0,
		float(fp.y - 1) * CELL_SIZE * 0.5)

## Scale the unit's MeshInstance3D to fill its footprint and slide it so the model
## centers over the whole covered block instead of sitting on the anchor cell.
##
## Applied to the VISUAL child only -- moving the unit node itself would change the
## world position BoardAdapter.cell_of() derives the anchor from. A 1x1 unit is a
## no-op, so normal units keep exactly the scale/offset the scene and the visual
## manager gave them. The pre-footprint scale is cached on first use so repeated
## calls (the visual manager re-applies materials + type scale on every refresh)
## never compound.
func apply_footprint_visual() -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	var fp := get_footprint()
	if fp == Vector2i.ONE:
		return
	if not _has_footprint_base_scale:
		_footprint_base_scale = mesh.scale
		_has_footprint_base_scale = true
	# Wide/deep by the span; height follows the larger axis so a 2x2 boss reads
	# as genuinely big rather than a flattened slab.
	var tall: float = float(maxi(fp.x, fp.y))
	mesh.scale = Vector3(
		_footprint_base_scale.x * float(fp.x),
		_footprint_base_scale.y * tall,
		_footprint_base_scale.z * float(fp.y))
	mesh.position = get_footprint_offset()

## True only for character-backed bosses; false for legacy / non-character units.
func is_boss() -> bool:
	if character_resource:
		return character_resource.is_boss
	return false


# --- AI behavior API --------------------------------------------------------
# Read by Bot/BossController; written once by the spawner. See the field block
# near the top of this script for the resolve-then-fall-back contract.

## Record this unit's home cell and combat behavior, resolved by the spawner.
## [param stance] is "aggressive" or "defensive" ("" falls back to the character
## default); [param aggro] is the defensive wake distance (< 0 falls back);
## [param leash] is the max cells from home the unit may move (< 0 falls back,
## and a fallen-back-to-negative resolves to untethered).
func configure_ai_behavior(p_home: Vector2i, stance: String = "", aggro: int = -1, leash: int = -1) -> void:
	home_cell = p_home
	# "dormant" = a neutral camp: holds and does NOTHING until it is attacked (see
	# provoked / take_damage), then behaves aggressively. Accepted here alongside the
	# two classic stances; anything else falls back to the character default.
	_ai_stance = stance if (stance == "aggressive" or stance == "defensive" or stance == "dormant") else _default_stance()
	_aggro_range = aggro if aggro >= 0 else _default_aggro()
	_leash_radius = leash if leash >= 0 else _default_leash()
	_ai_configured = true

## True once [method configure_ai_behavior] has run (the unit came through a spawner).
func has_ai_behavior() -> bool:
	return _ai_configured

## This unit's home / guard-post cell, or an invalid cell (-1,-1) if never set.
func get_home_cell() -> Vector2i:
	return home_cell

func has_home_cell() -> bool:
	return home_cell.x >= 0 and home_cell.y >= 0

## "aggressive" or "defensive". Falls back to the character default until configured.
func get_ai_stance() -> String:
	return _ai_stance if _ai_configured else _default_stance()

func is_aggressive() -> bool:
	return get_ai_stance() == "aggressive"

func is_defensive() -> bool:
	return get_ai_stance() == "defensive"

## A neutral camp unit that holds until attacked. While dormant AND not yet provoked the
## bot AI takes no action for it (see BotController.decide_action).
func is_dormant() -> bool:
	return get_ai_stance() == "dormant"

## Latched true the first time a dormant unit takes damage -- from then on it fights like
## an aggressive unit (attacks the nearest hostile of EITHER side).
var provoked: bool = false

## Defensive wake distance (Manhattan) from the home cell. Falls back until configured.
func get_aggro_range() -> int:
	return _aggro_range if _ai_configured else _default_aggro()

## Max cells from home this unit will move. < 0 means untethered (no leash).
func get_leash_radius() -> int:
	return _leash_radius if _ai_configured else _default_leash()

## True when a finite leash caps this unit's movement (an anchored / guarding unit).
func has_leash() -> bool:
	return get_leash_radius() >= 0

func _default_stance() -> String:
	if character_resource and character_resource.has_method("get_default_ai_stance"):
		return character_resource.get_default_ai_stance()
	return "aggressive"

func _default_aggro() -> int:
	if character_resource and character_resource.has_method("get_default_aggro_range"):
		return character_resource.get_default_aggro_range()
	return 0

func _default_leash() -> int:
	if character_resource and character_resource.has_method("get_default_leash_radius"):
		return character_resource.get_default_leash_radius()
	return -1

## The MovesetController child (cooldown / uses tracking), or null if absent.
func get_moveset_controller() -> Node:
	return get_node_or_null("MovesetController")

## The StatusController child (active status conditions), or null if absent.
func get_status_controller() -> Node:
	return get_node_or_null("StatusController")

## The AbilitySystem child (character abilities), or null when the character
## declares none / there is no character at all.
func get_ability_system() -> Node:
	return get_node_or_null("AbilitySystem")

## The character's movement profile once T6 adds get_movement_profile() to
## CharacterResource. Duck-typed so this compiles before that method exists;
## returns null when there is no character or the method is not yet available.
func get_movement_profile():
	if character_resource and character_resource.has_method("get_movement_profile"):
		return character_resource.get_movement_profile()
	return null

func get_moveset() -> Array[MoveResource]:
	"""The unit's moves, or an empty list when no character is assigned."""
	if character_resource:
		return character_resource.moveset
	var empty: Array[MoveResource] = []
	return empty

func get_move(slot: int) -> MoveResource:
	"""Move in the given slot (0..3), or null when empty/out of range."""
	if character_resource:
		return character_resource.get_move(slot)
	return null

func perform_move(slot: int, aim_cell: Vector2i, board_adapter, rng: RandomNumberGenerator = null) -> Dictionary:
	"""Resolve the move in [param slot] aimed at [param aim_cell] against the
	live board (a BoardAdapter). Delegates to MoveExecutor and returns its
	structured result dictionary (see MoveExecutor.execute).

	[param rng] is optional and trailing: left null (the single-player path) the
	executor makes its own randomized generator exactly as before; the networked
	command layer injects a seeded one (MatchRng.rng_for) so every peer resolves
	the same accuracy/crit rolls. Fully backward compatible."""
	var move := get_move(slot)
	if move == null:
		return {
			"success": false,
			"reason": "no_move_in_slot",
			"events": [],
			"cells": [],
		}
	var result: Dictionary = MoveExecutor.execute(move, self, board_adapter, aim_cell, rng)
	# Announce a successful cast so the visual layer animates EVERY move, not only
	# the ones that deal damage (damage_dealt covers those). Best-effort + guarded so
	# tests and headless runs without the autoload simply don't animate.
	if bool(result.get("success", false)) and typeof(GameEvents) == TYPE_OBJECT and GameEvents != null:
		GameEvents.move_performed.emit(self, move)
	return result

# Movement methods
func get_movement_range() -> int:
	"""Get unit's movement range"""
	return get_stat("movement")

func can_move_to(position: Vector3) -> bool:
	"""Check if unit can move to position (override in derived classes)"""
	return true

# Turn management
func process_turn_start() -> void:
	"""Called when unit's turn starts"""
	if unit_stats:
		unit_stats.process_modifier_durations()

func process_turn_end() -> void:
	"""Called when unit's turn ends"""
	# Reset action points or other per-turn resources
	pass
func _on_health_changed(old_health: int, new_health: int) -> void:
	"""Handle health changes"""
	# Notify visual manager directly
	if visual_manager:
		visual_manager._on_unit_health_changed(self, old_health, new_health)
	
	# Update health bar UI, check for death, etc.
	if new_health <= 0 and old_health > 0:
		_on_unit_died()

func _on_stat_changed(stat_name: String, old_value: int, new_value: int) -> void:
	"""Handle stat changes"""
	# Update UI, trigger effects, etc.
	pass

func _on_unit_died() -> void:
	"""Handle unit death: fire the death signals ONCE, then remove the unit from
	the board and scene so it stops occupying a cell, blocking turns, or lingering
	visually. Idempotent via _is_dead -- multiple observers of HP == 0 (take_damage,
	the health_changed signal) all funnel here but death only resolves once."""
	if _is_dead:
		return
	_is_dead = true

	# 1. Death-triggered abilities (ON_DEATH), FIRST -- while this unit is still in
	#    the tree, still standing on its cell, and still reported by the board's
	#    units_at(). Everything below takes that away: the signals in step 2
	#    unregister the unit from its owning Player and the turn system, and step 4
	#    hides and frees the node. A death burst has to explode from SOMEWHERE, so
	#    it must resolve before its origin stops existing. Running here also orders
	#    the victim's death throes ahead of the killer's ON_KILL, which
	#    unit_eliminated raises below. _is_dead above already makes this fire once.
	_fire_death_abilities()

	# 1b. Reward the unit that landed the killing blow, if this unit carries a
	#     kill_reward (the neutral camp creature does). Done here -- before we free
	#     ourselves in step 4 -- while the killer, who is on the opposing side and
	#     untouched by this death, is certainly still alive.
	_grant_kill_reward()

	# 2. Notify listeners while the node is still valid:
	#    - the owning Player removes it from owned_units (and self-eliminates when
	#      its last unit dies, which PlayerManager turns into a win/lose result),
	#    - the active turn system unregisters it and re-checks turn completion so a
	#      side whose last actable unit just died doesn't stall the turn.
	unit_died.emit(self)
	GameEvents.unit_eliminated.emit(self, null)  # null = no killer specified

	# 3. Tear down this unit's floating health bar (erases it from the visual
	#    manager's registry so no dangling reference remains).
	if visual_manager and visual_manager.has_method("cleanup_unit_visuals"):
		visual_manager.cleanup_unit_visuals(self)

	# 4. Remove the unit from play. Hide immediately so it disappears this frame,
	#    then free the node deferred -- deferring lets the signal handlers above
	#    (and anything mid-iteration over the board/units this same frame) unwind
	#    before the node is actually gone.
	visible = false
	if is_inside_tree() and not is_queued_for_deletion():
		queue_free()

## Raise ON_DEATH on this unit's OWN AbilitySystem (the victim's side of ON_KILL,
## which AbilitySystem raises for the killer instead). Called from
## _on_unit_died only, at the point documented there.
##
## Guarded end to end so nothing here can turn a death into an error: a unit whose
## character declares no abilities has no AbilitySystem child at all, a headless /
## pre-map run has no live board (ability effects need one -- AbilityResource.
## run_effects no-ops on null anyway, so there is nothing to gain by calling), and
## a node already on its way out is left alone.
func _fire_death_abilities() -> void:
	if is_queued_for_deletion():
		return
	# Deliberately untyped: get_ability_system() is declared -> Node, and calling
	# trigger() on a Node-typed variable would not compile.
	var ability_system = get_ability_system()
	if ability_system == null or not ability_system.has_method("trigger"):
		return
	var board = CombatServices.board() if CombatServices else null
	if board == null:
		return
	ability_system.trigger(AbilityTrigger.Trigger.ON_DEATH, self, board)

## Remember the last unit to damage us, so a kill_reward can credit the killer. Only
## records when WE are the defender and the attacker is a distinct, still-valid unit.
## Fires for every unit (the signal is global) but is a cheap no-op unless it is us.
func _on_any_damage_dealt(attacker, defender, _amount) -> void:
	if defender != self:
		return
	if attacker == null or attacker == self or not is_instance_valid(attacker):
		return
	_last_damager = attacker

## Grant this unit's kill_reward to whoever last damaged it. Fully null-safe: no
## reward, or no valid killer, or a killer without a StatusController, all simply do
## nothing. The killer receives a fresh DUPLICATE so the shared authoring resource is
## never mutated (mirrors ApplyStatusEffect). Called once from _on_unit_died.
func _grant_kill_reward() -> void:
	if kill_reward == null:
		return
	if _last_damager == null or not is_instance_valid(_last_damager):
		return
	var killer: Unit = _last_damager
	if not killer.has_method("get_status_controller"):
		return
	# Deliberately untyped: get_status_controller() is declared -> Node, and calling
	# add_status() on a Node-typed variable would not compile.
	var controller = killer.get_status_controller()
	if controller == null or not controller.has_method("add_status"):
		return
	controller.add_status(kill_reward.duplicate(true))

# Visual feedback (updated to use visual manager)
func _on_unit_selected(unit: Unit) -> void:
	if unit == self and visual_manager:
		visual_manager.apply_selection_visual(self, true)

func _on_unit_deselected(unit: Unit) -> void:
	if unit == self and visual_manager:
		visual_manager.apply_selection_visual(self, false)

func _apply_selection_visual(selected: bool) -> void:
	"""Legacy method - now delegates to visual manager"""
	if visual_manager:
		visual_manager.apply_selection_visual(self, selected)

# Debug helpers
func _to_string() -> String:
	if unit_stats:
		return str(unit_stats)
	return "Unit: No stats component"

func get_debug_info() -> Dictionary:
	"""Get debug information about the unit"""
	var info = {
		"name": get_display_name(),
		"alive": is_alive(),
		"has_turn": has_turn,
		"position": position,
		"stats_component": unit_stats != null
	}
	
	if unit_stats:
		info.merge(unit_stats.get_debug_info())
	
	return info
