extends RefCounted

## STORY TEST FIXTURES. A new journey now starts at the very beginning of the story OPENING
## (docs/design/DECISIONS.md #14): no creature, the mother's send-off plays on the first Oakvale
## boot, and the Mossway's trainer / recruit only appear once the opening is over. Suites that
## exercise the overworld's mechanics (walking, the grass, trainers, battles) rather than the
## opening itself start from a journey PAST the opening, with the M1 slice's two-member party.

const LEGACY_PARTY: Array[String] = ["vineweave", "blightcap"]

## Every flag the opening sets, in story order (build_story_content.gd F_* constants).
const OPENING_FLAGS: Array[String] = [
	"opening.sent_off", "opening.arrived_crownhaven", "opening.ceremony", "opening.starter_received",
	"key.bonding_shard", "opening.attack", "opening.researcher_taken", "opening.raiders_fled",
	"opening.chase", "opening.allies_met", "opening.ruins_seen", "opening.first_fight_won",
	"opening.complete", "act1.find_rowan",
]


## Mark [param s] as past the opening and give it [param party] when it has no members yet (the
## HERO's own record -- a new journey's, docs/design/HUMANS.md -- does not count: he is no partner).
static func past_opening(s: StoryState, party: Array[String] = LEGACY_PARTY) -> StoryState:
	for f in OPENING_FLAGS:
		s.set_flag(f, 1)
	if s.capped_count() == 0:
		for cid in party:
			s.add_member(cid)
	return s


## Force every encounter zone of [param area] to [param mode] (EncounterZone.Mode) -- e.g. the
## Mossway's grass HIDDEN for a suite about the per-step roll. The area resource is the cached,
## shared one: ALWAYS undo with [method restore_zone_modes] (after_each). Returns the old modes.
static func set_zone_modes(area: OverworldAreaResource, mode: int) -> Array:
	var old: Array = []
	if area == null:
		return old
	for z in area.zones():
		old.append(z.mode)
		z.mode = mode
	return old


static func restore_zone_modes(area: OverworldAreaResource, old: Array) -> void:
	if area == null:
		return
	var zs: Array[EncounterZone] = area.zones()
	for i in range(mini(zs.size(), old.size())):
		zs[i].mode = old[i]


## Only the send-off: the journey can leave Oakvale (no intro on boot), nothing else has happened.
static func sent_off(s: StoryState) -> StoryState:
	s.set_flag("opening.sent_off", 1)
	return s
