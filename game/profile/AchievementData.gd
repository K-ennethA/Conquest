class_name AchievementData
extends RefCounted

## The launch achievement table plus the pure logic that decides whether each one is
## earned. Data-only (a static table + a stateless [method is_satisfied] check), so it can
## be read by [PlayerProfile] (to unlock + toast), the profile screen (to render the grid)
## and the tests, with no instance and no engine dependency.
##
## Each row is a plain Dictionary:
##   id    String  stable key stored in the profile (never reorder-fragile)
##   name  String  short display title
##   desc  String  one-line "how to earn it" hint
##   icon  String  a single emoji / glyph used as the card badge
##
## Whether an achievement is currently earned is decided by [method is_satisfied], which
## scores an achievement id against a CONTEXT dictionary assembled by PlayerProfile (its
## stats plus a few retroactively-derived counts -- campaign clears, a challenge win, custom
## maps on disk, owned skins). Keeping the check pure + retroactive means a player who did
## the deed BEFORE this system shipped still unlocks it the first time their profile loads.


## The ordered achievement table. Returns a fresh array each call.
static func all() -> Array:
	return [
		{ "id": "first_victory", "name": "First Blood", "icon": "⚔",
			"desc": "Win your first battle." },
		{ "id": "win_10", "name": "Seasoned", "icon": "🎖",
			"desc": "Win 10 battles." },
		{ "id": "win_50", "name": "Veteran Campaigner", "icon": "🏅",
			"desc": "Win 50 battles." },
		{ "id": "first_campaign_chapter", "name": "Into the Forest", "icon": "🌲",
			"desc": "Clear your first campaign chapter." },
		{ "id": "campaign_complete", "name": "Blightbreaker", "icon": "👑",
			"desc": "Clear every campaign chapter." },
		{ "id": "first_arena_run", "name": "Challenger", "icon": "🛡",
			"desc": "Win a round in the Arena." },
		{ "id": "arena_standard_clear", "name": "Arena Champion", "icon": "🏆",
			"desc": "Clear a full Arena run." },
		{ "id": "first_challenge_win", "name": "Gauntlet Runner", "icon": "🎯",
			"desc": "Beat a community challenge." },
		{ "id": "perfect_challenge", "name": "Flawless", "icon": "✨",
			"desc": "Beat a challenge without losing a unit." },
		{ "id": "first_map_created", "name": "Cartographer", "icon": "🗺",
			"desc": "Create and save a custom map." },
		{ "id": "defeat_eldroot", "name": "Heartwood's End", "icon": "🌳",
			"desc": "Fell Eldroot at the heart of the Forgotten Forest." },
		{ "id": "collector_5_skins", "name": "Collector", "icon": "🎨",
			"desc": "Own 5 unit skins." },
	]


## The row for [param id], or {} when unknown.
static func get_row(id: String) -> Dictionary:
	for row in all():
		if String(row.get("id", "")) == id:
			return row
	return {}


## Every achievement id, in table order.
static func ids() -> Array:
	var out: Array = []
	for row in all():
		out.append(String(row.get("id", "")))
	return out


## True when the achievement [param id] is EARNED given [param ctx], a snapshot dictionary
## PlayerProfile assembles. Unknown ids and a missing key both read as not-earned. Pure and
## side-effect free, so it is safe to call on every relevant event and on profile load.
static func is_satisfied(id: String, ctx: Dictionary) -> bool:
	match id:
		"first_victory":
			return int(ctx.get("battles_won", 0)) >= 1
		"win_10":
			return int(ctx.get("battles_won", 0)) >= 10
		"win_50":
			return int(ctx.get("battles_won", 0)) >= 50
		"first_campaign_chapter":
			return int(ctx.get("campaign_cleared_count", 0)) >= 1
		"campaign_complete":
			return bool(ctx.get("campaign_complete", false))
		"first_arena_run":
			return int(ctx.get("arena_rounds_won", 0)) >= 1
		"arena_standard_clear":
			return int(ctx.get("arena_runs_cleared", 0)) >= 1
		"first_challenge_win":
			return bool(ctx.get("challenge_won", false))
		"perfect_challenge":
			return int(ctx.get("perfect_challenges", 0)) >= 1
		"first_map_created":
			return int(ctx.get("maps_created", 0)) >= 1
		"defeat_eldroot":
			return bool(ctx.get("eldroot_defeated", false))
		"collector_5_skins":
			return int(ctx.get("owned_skins_count", 0)) >= 5
		_:
			return false
