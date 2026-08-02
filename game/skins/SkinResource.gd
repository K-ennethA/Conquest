extends Resource
class_name SkinResource

## A single cosmetic variant of a roster character — a "skin".
##
## A skin never changes stats, moves or abilities: it is pure vanity. Everything
## that makes it distinct lives here as data, so authoring one is creating a new
## .tres under game/skins/content/ (no script needed). Two application modes:
##
##   * [member tint] only (the common, cheap case): the character's DEFAULT model
##     is kept and every mesh surface gets an albedo-multiplied material override.
##     A warm-red "Emberroot" Vineweave is just the base Vineweave model with a
##     red tint — no new art required.
##   * [member model_scene] (optional): a full model swap, used the same way the
##     character's own model_scene is (same yaw/scale/facing pipeline in Unit).
##
## ECONOMY: skins are unlocked with EARNED points only (see PlayerProfile). A skin
## is either directly buyable ([member price] > 0) or gacha-only ([member price]
## == 0, obtainable exclusively from a gacha roll). No real money is involved; a
## future premium currency can slot in beside points without touching this schema.

## Rarity tier. Drives the gacha weight (see [method rarity_weight]) and the card
## colour in the Collection screen. Authored as an int in the .tres (0/1/2).
enum Rarity { COMMON, RARE, EPIC }

## The default (no-op) tint: pure white multiplies a material's albedo by 1,
## leaving the base model's colours untouched. A skin whose tint equals this and
## has no model_scene is a content bug (it would look identical to default).
const DEFAULT_TINT: Color = Color(1.0, 1.0, 1.0, 1.0)

## Gacha weights per rarity. COMMON is the bulk of the pool, EPIC the jackpot.
## Kept here (not the Collection UI) so the weighting is one reviewable table the
## tests can assert against.
const WEIGHT_COMMON: int = 70
const WEIGHT_RARE: int = 25
const WEIGHT_EPIC: int = 5

@export_group("Identity")
## Globally UNIQUE, stable skin id (e.g. &"vineweave_emberroot"). This is what
## PlayerProfile stores as owned/equipped, so it must never change once shipped.
@export var id: StringName = &""
## The roster character this skin belongs to (must resolve in CharacterLibrary).
@export var character_id: StringName = &""
@export var display_name: String = "New Skin"
@export_multiline var description: String = ""

@export_group("Economy")
@export var rarity: Rarity = Rarity.COMMON
## Direct-buy cost in points. 0 = GACHA-ONLY (cannot be bought outright).
@export var price: int = 0

@export_group("Appearance")
## Optional full-model override. When set, Unit swaps the character's model for
## this one (same orient/scale pipeline). Leave null for a tint-only recolor.
@export var model_scene: PackedScene
## Albedo tint multiplied over the DEFAULT model when [member model_scene] is
## null. [constant DEFAULT_TINT] (white) = no visible change.
@export var tint: Color = DEFAULT_TINT


## Gacha draw weight for this skin's rarity. Higher = more likely.
func rarity_weight() -> int:
	match rarity:
		Rarity.COMMON:
			return WEIGHT_COMMON
		Rarity.RARE:
			return WEIGHT_RARE
		Rarity.EPIC:
			return WEIGHT_EPIC
	return WEIGHT_COMMON


## Human-readable rarity name (for UI / debugging).
func rarity_name() -> String:
	match rarity:
		Rarity.COMMON:
			return "Common"
		Rarity.RARE:
			return "Rare"
		Rarity.EPIC:
			return "Epic"
	return "Common"


## True when this skin recolors the default model (has a non-default tint and no
## full-model override). A model_scene skin returns false here — it replaces the
## model instead of tinting it.
func has_tint() -> bool:
	return model_scene == null and tint != DEFAULT_TINT


## True when the skin can be bought outright (as opposed to gacha-only).
func is_buyable() -> bool:
	return price > 0


## Content validation for the catalog / tests.
func validate() -> Dictionary:
	var issues: Array[String] = []
	if String(id).is_empty():
		issues.append("id is required")
	if String(character_id).is_empty():
		issues.append("character_id is required")
	if display_name.is_empty():
		issues.append("display_name is required")
	if price < 0:
		issues.append("price cannot be negative")
	if model_scene == null and not has_tint():
		issues.append("skin has neither a model_scene nor a distinct tint (would look identical to default)")
	return { "valid": issues.is_empty(), "issues": issues }
