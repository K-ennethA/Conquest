extends MoveEffect
class_name SummonEffect

## Raises [member count] units of [member character_id] onto free cells near the aim,
## owned by the CASTER's player. The Necromancer's identity: Reanimate (an ON_KILL
## ability that raises one undead on the slain foe's cell) and Undying Legion (a move
## that raises a small horde beside the caster) both use this.
##
## The actual spawn + ownership + turn-registration is delegated to
## [method GameWorldManager.summon_unit] (found via the "game_world_manager" group), so
## this effect stays a thin, headless-safe describer: with no live GameWorldManager
## (unit tests, mock harnesses) it simply summons nothing rather than erroring.
##
## NOTE: summons belong to the caster's player and are PLAYER-CONTROLLED. The turn/AI
## architecture drives whole AI players, not individual units on a human's side, so a
## truly autonomous "charge the enemy on its own" ally is not expressible yet -- the
## stance is carried through for the day that becomes possible. See the survey notes.

## How many bodies to raise.
@export var count: int = 1
## The roster id of the unit to raise (a melee-only "undead" character by default).
@export var character_id: StringName = &"undead"
## AI stance stamped on each summon (forward-looking; player-owned summons are commanded
## by the player today).
@export var stance: String = "aggressive"


func apply(ctx: MoveContext) -> void:
	if ctx == null or ctx.caster == null:
		return
	if not ctx.caster.has_method("get_owner_player"):
		return
	var owner = ctx.caster.get_owner_player()
	if owner == null:
		# An ownerless caster (a mock, a unit mid-teardown) simply raises nothing. The
		# empty ctx.results IS the report -- see the note on the no-free-cell branch below.
		return
	var pid: int = int(owner.player_id)

	var gwm = _summoner()
	if gwm == null:
		# Headless / mock harnesses legitimately have no world, so stay quiet there; in a
		# live battle this is a real failure worth surfacing rather than silently no-op'ing.
		if Engine.get_main_loop() is SceneTree and (Engine.get_main_loop() as SceneTree).current_scene != null:
			push_warning("SummonEffect: no summoner (GameWorldManager.summon_unit) reachable -- nothing raised.")
		return

	var origin: Vector2i = ctx.aim_cell
	var cells: Array = _summon_cells(ctx, origin, count)
	if cells.is_empty():
		# "The board around the caster is crowded, so the summon fizzles" is a normal
		# GAMEPLAY outcome, not a fault -- it happens whenever a necromancer casts into a
		# packed melee. Reporting it through the engine log put an expected combat result
		# in the debugger; the caller sees it as no summon events in ctx.results.
		ctx.log_event({
			"effect": "summon_fizzled",
			"cell": origin,
			"character_id": String(character_id),
			"reason": "no free cell",
		})
		return
	# Optional deterministic id base for networked play. Read duck-typed off the
	# context so single-player (a plain MoveContext that has no such property) is
	# untouched: Object.get() returns null for a missing property, and a null base
	# yields net_id -1 (current behaviour -- CommandApplier then assigns reactively).
	var net_base = ctx.get("summon_net_base")
	var index: int = 0
	for cell in cells:
		var net_id: int = (int(net_base) + index) if net_base != null else -1
		var unit = gwm.summon_unit(character_id, cell, pid, stance, net_id)
		if unit == null:
			push_warning("SummonEffect: summon_unit('%s') at %s returned null." % [String(character_id), str(cell)])
			continue
		ctx.log_event({
			"effect": "summon",
			"target": unit,
			"cell": cell,
			"character_id": String(character_id),
			"net_id": net_id,
		})
		index += 1


## Whatever can actually perform a summon this frame -- i.e. a node exposing
## summon_unit(). Resolved defensively because a single lookup is a single point of
## failure: the group is the fast path, but if the manager somehow isn't in it (scene
## rebuilt, load order, a different battle root) we fall back to scanning the current
## scene rather than silently raising nothing. Null in headless/mocked runs.
func _summoner():
	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree := loop as SceneTree

	# Fast path: the manager registers itself in this group on _ready.
	var node = tree.get_first_node_in_group("game_world_manager")
	if node != null and node.has_method("summon_unit"):
		return node

	# Fallback: find any node in the live scene that can summon.
	if tree.current_scene != null:
		var found = _find_summoner_in(tree.current_scene)
		if found != null:
			return found
	return null


## Depth-first search for a node exposing summon_unit(). Small scenes, run only when the
## group lookup missed, so the cost is negligible.
func _find_summoner_in(node: Node):
	if node == null:
		return null
	if node.has_method("summon_unit"):
		return node
	for child in node.get_children():
		var found = _find_summoner_in(child)
		if found != null:
			return found
	return null


## Up to [param n] free cells spiralling out from [param origin] (the aim / victim cell),
## skipping out-of-bounds and occupied cells so summons never stack on a corpse or a
## standing unit. The origin itself is included only if free -- at an ON_KILL raise the
## victim still occupies it this frame, so the raise lands on an adjacent cell.
func _summon_cells(ctx: MoveContext, origin: Vector2i, n: int) -> Array:
	var out: Array = []
	var board = ctx.board
	var ring: int = 0
	while out.size() < n and ring <= 6:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if out.size() >= n:
					break
				# Only the current ring's PERIMETER, so cells fill nearest-first.
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var cell: Vector2i = origin + Vector2i(dx, dy)
				if cell in out:
					continue
				if not _cell_is_free(board, cell):
					continue
				out.append(cell)
		ring += 1
	return out


## True when [param cell] is a legal, empty landing spot. Duck-typed / null-safe so a
## bare mock board (or none) never blocks the spiral.
func _cell_is_free(board, cell: Vector2i) -> bool:
	if board == null:
		return true
	if board.has_method("in_bounds") and not board.in_bounds(cell):
		return false
	if board.has_method("is_occupied") and board.is_occupied(cell):
		return false
	if board.has_method("is_blocked") and board.is_blocked(cell):
		return false
	return true


func describe() -> String:
	if description_override != "":
		return description_override
	if count == 1:
		return "Raise an undead servant"
	return "Raise %d undead servants" % count
