extends RefCounted
class_name MovementLibrary

## Convenience factory that seeds a few example [MovementProfile]s in code.
##
## These are starting content / test fixtures — shipping content should author
## profiles as .tres files, which this system fully supports. Every profile here
## is expressible purely as data, demonstrating the format. Flavor is neutral.

## Foot soldier: walks the cardinal directions, short reach.
static func infantry() -> MovementProfile:
	return MovementProfile.create(
		&"infantry", "Infantry",
		CombatTypes.MovementKind.GROUND, 3, MovementProfile.Shape.ORTHOGONAL)


## Mounted unit: moves in all eight directions with a long reach.
static func cavalry() -> MovementProfile:
	return MovementProfile.create(
		&"cavalry", "Cavalry",
		CombatTypes.MovementKind.GROUND, 5, MovementProfile.Shape.ALL8)


## Airborne unit: eight-directional and flies over walls, but not through units.
static func flier() -> MovementProfile:
	return MovementProfile.create(
		&"flier", "Flier",
		CombatTypes.MovementKind.FLYING, 4, MovementProfile.Shape.ALL8)


## Skirmisher that vaults in fixed L-jumps, clearing whatever lies between.
static func ranger_knight() -> MovementProfile:
	return MovementProfile.create(
		&"ranger_knight", "Vaulting Skirmisher",
		CombatTypes.MovementKind.GROUND, 2, MovementProfile.Shape.KNIGHT)


## Short-range teleport that phases past any obstacle to an open cell.
static func blink() -> MovementProfile:
	return MovementProfile.create(
		&"blink", "Blink",
		CombatTypes.MovementKind.PHASING, 3, MovementProfile.Shape.TELEPORT)


## All sample profiles, for iteration / previews.
static func all() -> Array[MovementProfile]:
	return [infantry(), cavalry(), flier(), ranger_knight(), blink()]
