extends BoardAdapter
class_name DuelBoard

## The duel's board: two STATIONS on one floor, where everything is in reach
## (docs/design/DUEL_BATTLE.md §3.3). Installed as THE live board through
## [method CombatServices.install_board], so the whole combat core (MoveExecutor,
## DamageMath, statuses, abilities, weather, per-turn ticks) runs on it unchanged.
##
## - Station A is (0,0,0) (challenger / player), station B is (gap,0,0) (foe). Units stand
##   at real grid cell centres, so [method BoardAdapter.cell_of] (derived from world
##   position), MoveFX and floating combat text work unmodified.
## - [method reach_is_unbounded] is the one hook [TargetingPattern] asks: the range test is
##   skipped, everything else (landing constraints, LOS) still applies.
## - Only the ACTIVE combatants exist for the board (a benched party member is invisible to
##   it); the units provider is whatever the owning [DuelBattle] hands in.
## - Stations never change: [method move_unit] is a no-op and [method can_fit] only admits a
##   unit's own station.

const STATION_A := Vector3i(0, 0, 0)

var _gap: int = 4


## [param units_provider] returns the ACTIVE combatants (a Callable / Array, see
## [BoardAdapter]); [param gap] is [member DuelRuleset.station_gap].
func _init(grid, units_provider, gap: int = 4) -> void:
	super(grid, units_provider)
	_gap = maxi(2, gap)


## THE hook: distance is abstract in a duel.
func reach_is_unbounded() -> bool:
	return true


## Station of side [param side] (0 = A, 1 = B).
func station(side: int) -> Vector3i:
	return STATION_A if side == 0 else Vector3i(_gap, 0, 0)


func stations() -> Array[Vector3i]:
	return [station(0), station(1)]


func station_gap() -> int:
	return _gap


## Which station [param unit] stands on (0 / 1), or -1 when it is off both.
func side_of(unit) -> int:
	var c := cell_of(unit)
	if c == station(0):
		return 0
	if c == station(1):
		return 1
	return -1


## World position of [param side]'s station centre (floor 0).
func station_world(side: int) -> Vector3:
	return cell_to_world(station(side))


## Stations never change in a duel.
func move_unit(_unit, _to_cell: Vector3i) -> void:
	pass


## Nobody lands anywhere but their own station.
func can_fit(unit, anchor: Vector3i) -> bool:
	return unit != null and anchor == cell_of(unit)


## Abstract space: every cell on the ground floor exists (AoE cells beyond the stations
## simply hold nobody), independent of the grid resource's authored size.
func in_bounds(cell: Vector3i) -> bool:
	return cell.z == 0


func has_tile(cell: Vector3i) -> bool:
	return cell.z == 0


## One floor, no walls.
func blocks_los_at(_cell: Vector3i) -> bool:
	return false


func is_solid_ceiling(_cell: Vector3i) -> bool:
	return false


func floor_count() -> int:
	return 1
