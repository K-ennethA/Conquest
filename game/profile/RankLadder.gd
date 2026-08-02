class_name RankLadder
extends RefCounted

## The LOCAL progression ladder: a player's rank is derived purely from their
## lifetime [b]points_total[/b] (never the spendable balance -- spending on skins must
## never demote you). Seven ascending tiers, each a points threshold you cross once and
## keep. Pure static maths so the ladder can be read from [PlayerProfile], the profile
## screen and the tests without an instance.
##
## NOTE: this is the SOLO / cosmetic-economy ladder that ships now. A COMPETITIVE rank
## (ELO-style, won and lost against other players) arrives with ranked multiplayer
## (task #106) and will live in a SEPARATE field -- it is deliberately not modelled here,
## so climbing this ladder can never be confused with a competitive standing.


## The ordered tier table, lowest first. Each row is {name, threshold} where threshold is
## the lifetime points at which the tier is reached. Returns a fresh array each call.
static func tiers() -> Array:
	return [
		{ "name": "Recruit", "threshold": 0 },
		{ "name": "Soldier", "threshold": 500 },
		{ "name": "Veteran", "threshold": 1500 },
		{ "name": "Knight", "threshold": 3500 },
		{ "name": "Champion", "threshold": 7000 },
		{ "name": "Warlord", "threshold": 12000 },
		{ "name": "Mythic", "threshold": 20000 },
	]


## Index of the tier [param points] currently sits in (0..tiers-1).
static func rank_index(points: int) -> int:
	var list: Array = tiers()
	var idx: int = 0
	for i in range(list.size()):
		if points >= int(list[i].get("threshold", 0)):
			idx = i
		else:
			break
	return idx


## The display name of the rank for [param points] (e.g. "Veteran").
static func rank_for(points: int) -> String:
	return String(tiers()[rank_index(points)].get("name", "Recruit"))


## The points threshold of the NEXT tier up, or -1 when already at the top tier.
static func next_threshold(points: int) -> int:
	var list: Array = tiers()
	var idx: int = rank_index(points)
	if idx + 1 >= list.size():
		return -1
	return int(list[idx + 1].get("threshold", 0))


## The points threshold of the tier [param points] currently occupies (its floor).
static func current_threshold(points: int) -> int:
	return int(tiers()[rank_index(points)].get("threshold", 0))


## Fractional progress 0..1 from the current tier's floor toward the next tier's
## threshold. Returns 1.0 at the top tier (nothing further to climb).
static func progress_in_rank(points: int) -> float:
	var floor_pts: int = current_threshold(points)
	var ceil_pts: int = next_threshold(points)
	if ceil_pts < 0:
		return 1.0
	var span: int = ceil_pts - floor_pts
	if span <= 0:
		return 1.0
	return clampf(float(points - floor_pts) / float(span), 0.0, 1.0)


## Points still needed to reach the next tier, or 0 when at the top.
static func points_to_next(points: int) -> int:
	var ceil_pts: int = next_threshold(points)
	if ceil_pts < 0:
		return 0
	return maxi(0, ceil_pts - points)
