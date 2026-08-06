extends RefCounted

## Test doubles for the FOG OF WAR presentation suites.
##
## Kept OUT of `tests/helpers/test_doubles.gd` on purpose: that file's doubles are
## duck-typed against the combat pipeline and tests/README warns that adding a method to one
## silently reroutes every suite using it. This is a different contract entirely -- the
## [VisionSystem] API ([code]fog_enabled[/code] / [code]is_cell_visible[/code] /
## [code]is_unit_visible[/code] / [code]visible_cells[/code] / [signal vision_changed]) --
## so it gets its own file.
##
## WHY A STUB AT ALL: the vision core lands separately from the presentation layer this
## exercises. Injecting the stub through [method FogOfWarOverlay.set_vision_override] means
## these suites pin the LOOK and the REFUSALS against a vision oracle they control, on any
## board, without waiting on (or coupling to) the core's implementation. The real core is
## verified against the same API surface.
##
## A [RefCounted], not a Node, so nothing here can orphan (tests/README rule 2).


## The vision oracle. Hidden sets are PER PLAYER -- that is what lets a hotseat test prove
## the shroud actually flips when the seat changes, rather than merely repainting.
class StubVision:
	extends RefCounted

	signal vision_changed

	## What [method FogOfWarOverlay.fog_active] reads. Flip it to prove the layer costs
	## nothing (and draws nothing) with fog authored off.
	var enabled: bool = true

	## player_id -> { Vector2i: true }.
	var hidden_cells: Dictionary = {}
	## player_id -> { Unit: true }.
	var hidden_units: Dictionary = {}

	## Every cell on the board, so [method visible_cells] can answer as a real core would.
	var board_cells: Array[Vector2i] = []

	## Counts calls, so a test can prove a gate is read LIVE at event time rather than from
	## a set snapshotted at the last repaint (the reveal-on-attack contract).
	var unit_queries: int = 0

	func set_board(cols: int, rows: int) -> void:
		board_cells.clear()
		for col in range(cols):
			for row in range(rows):
				board_cells.append(Vector2i(col, row))

	func hide_cells(player_id: int, cells: Array) -> void:
		var set: Dictionary = hidden_cells.get(player_id, {})
		for cell in cells:
			set[cell] = true
		hidden_cells[player_id] = set

	func show_cells(player_id: int, cells: Array) -> void:
		var set: Dictionary = hidden_cells.get(player_id, {})
		for cell in cells:
			set.erase(cell)
		hidden_cells[player_id] = set

	func hide_unit(player_id: int, unit) -> void:
		var set: Dictionary = hidden_units.get(player_id, {})
		set[unit] = true
		hidden_units[player_id] = set

	func show_unit(player_id: int, unit) -> void:
		var set: Dictionary = hidden_units.get(player_id, {})
		set.erase(unit)
		hidden_units[player_id] = set

	# --- The VisionSystem API ------------------------------------------------

	func fog_enabled() -> bool:
		return enabled

	func is_cell_visible(player_id: int, cell: Vector2i) -> bool:
		return not (hidden_cells.get(player_id, {}) as Dictionary).has(cell)

	func is_unit_visible(player_id: int, unit) -> bool:
		unit_queries += 1
		return not (hidden_units.get(player_id, {}) as Dictionary).has(unit)

	func visible_cells(player_id: int) -> Array:
		var out: Array = []
		for cell in board_cells:
			if is_cell_visible(player_id, cell):
				out.append(cell)
		return out

	# --- Driving -------------------------------------------------------------

	## Announce that vision changed, exactly as the core does when a unit moves, a
	## concealing effect lapses, or an attacker reveals itself.
	func notify() -> void:
		vision_changed.emit()


## A core that offers ONLY the per-cell probe -- no [code]visible_cells[/code]. Proves the
## overlay's fallback sweep, so the layer does not hard-depend on the batch call.
class ProbeOnlyVision:
	extends RefCounted

	signal vision_changed

	var enabled: bool = true
	var hidden: Dictionary = {}

	func hide_cells(cells: Array) -> void:
		for cell in cells:
			hidden[cell] = true

	func fog_enabled() -> bool:
		return enabled

	func is_cell_visible(_player_id: int, cell: Vector2i) -> bool:
		return not hidden.has(cell)

	func is_unit_visible(_player_id: int, _unit) -> bool:
		return true
