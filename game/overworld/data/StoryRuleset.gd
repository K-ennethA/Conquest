class_name StoryRuleset
extends Resource

## STORY MODE'S TUNING SURFACE (CONQUEST.md rule 11: a mode's knobs live on its ruleset
## resource). Retuning the overworld pace, the encounter rate or befriending odds is an edit to
## game/overworld/content/story_ruleset.tres.

const DEFAULT_PATH := "res://game/overworld/content/story_ruleset.tres"

@export_group("Journey start")
@export var start_area: StringName = &"oakvale"
@export var start_entry: StringName = &"start"
## Members a new journey starts with. EMPTY in the shipped story: the hero is a villager with no
## creature until the shard ceremony in Crownhaven (docs/design/DECISIONS.md #14).
@export var starting_party: Array[StringName] = []
@export var starting_gold: int = 100
@export_range(1, 12) var party_cap: int = 6

@export_group("Walking")
## Seconds per cell walking / running (run = hold fast_forward: Shift / R3) -- the LEGACY grid
## pace, used only by the "current" overworld feel preset ([OverworldFeel]). The shipped feel
## derives its pace from the hero clip strides below (speed first, seconds per cell from it).
@export var walk_step_seconds: float = 0.22
@export var run_step_seconds: float = 0.12
## The HERO's locomotion clips in game units (shipped wren_forge.glb): stride (metres per full
## two-step cycle) and cycle length. Forge's zero-slip ball-contact report (forge
## projects/conquest-units/rigged/wren.json: walk 0.8103 m / 1.0833 s, run 2.3333 m / 0.5 s)
## times the export's cell fit 1.02823; the glb itself measures walk 0.833 m (flat-stance ankle
## speed 0.7691 m/s x 1.0833 s). Ground speed = stride / cycle x the feel's clip rate: a hero
## model with a different stride must update these or its feet slide.
@export var hero_walk_stride_m: float = 0.8332
@export var hero_walk_cycle_seconds: float = 1.0833
@export var hero_run_stride_m: float = 2.3992
@export var hero_run_cycle_seconds: float = 0.5
## A tap on a new direction only TURNS; holding longer than this walks.
@export var turn_hold_seconds: float = 0.09

@export_group("Encounters")
## Steps after an area entry / a battle before grass may roll again.
@export var grace_steps: int = 3

@export_group("Befriending")
## Base chance a defeated wild unit offers to join (rolled on VICTORY off the battle's seed).
@export_range(0.0, 1.0) var befriend_join_chance: float = 0.35
## Added when the wild unit was subdued (left at 1 HP / KO'd by a subdue move -- DUEL M2).
@export_range(0.0, 1.0) var subdue_join_bonus: float = 0.35

@export_group("Economy")
## Gold for each foe defeated in a WILD encounter (a won grass duel: one foe). Trainers and scripted
## battles pay their authored purse ([member BattleSpec.reward_gold]) instead.
@export var wild_gold_per_foe: int = 15
## Gold for each foe defeated in any NON-wild story battle, on top of its authored purse (0 = the
## purse only).
@export var battle_gold_per_foe: int = 0
## Fraction of an item's price a merchant pays when you sell it back (a [ShopResource] may name
## its own).
@export_range(0.0, 1.0, 0.01) var sell_ratio: float = 0.5
## Most of one item the story bag holds (a purchase past it is refused: "bag full").
@export_range(1, 999) var bag_stack_cap: int = 99

@export_group("Stakes")
## Gold lost on a whiteout (0 = Q2 default: lose nothing but position).
@export var whiteout_gold_penalty: int = 0

@export_group("Difficulty tiers")
## The tier a journey gets when nothing chose one (tools, tests, [method StoryController.new_journey]
## without a tier). The New Journey screen always asks. "classic" or "casual".
@export_enum("classic", "casual") var default_tier: String = "casual"
## CASUAL: gold a Wayshrine asks to revive EACH knocked-out member (the living are still rested for
## free). 0 = revives are free (the pre-tier behaviour). Revive items work in both tiers.
@export var revive_fee_per_member: int = 50
## A whiteout (you wake at the Wayshrine) also revives the knocked-out, in both tiers -- a lost
## battle already cost you your position (and [member whiteout_gold_penalty]). Off: they stay down
## until revived.
@export var whiteout_revives: bool = true
## A member knocked out in a friendly SPAR (never permadeath) leaves it at 1 HP instead of
## knocked out: a friendly never costs a revive. Off: it stays knocked out like any KO.
@export var spar_ko_recovers: bool = true
## CLASSIC: a battle that would leave the journey with NO living member (everyone fallen) is a
## GAME OVER (back to the last save) instead of a whiteout with nobody left to fight.
@export var classic_wipe_is_game_over: bool = true

@export_group("Sparring")
## A SPARRING PARTNER's cooldown ([StorySparring]; DECISIONS.md #33): after a bout with one partner
## (a spar whose script asks [code]spar_ready("<encounter id>")[/code]), that partner is ready again
## only once the journey has RESTED this many times since (a Wayshrine / healer / whiteout rest --
## [member StoryState.rests]). Spars award Growth by the ordinary story rules, so this is what keeps
## a friendly bout from being an endless Growth farm. 0 = no rest needed.
@export_range(0, 10) var spar_cooldown_rests: int = 1
## ...and walked at least this many steps since the bout ([member StoryState.steps]). 0 = no walk
## needed. Both must hold when both are set.
@export_range(0, 5000) var spar_cooldown_steps: int = 0


static func load_default() -> StoryRuleset:
	if ResourceLoader.exists(DEFAULT_PATH):
		var r := load(DEFAULT_PATH) as StoryRuleset
		if r != null:
			return r
	return StoryRuleset.new()
