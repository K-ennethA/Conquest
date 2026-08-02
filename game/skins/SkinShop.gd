extends RefCounted
class_name SkinShop

## The points ECONOMY over [SkinLibrary]: buying, equipping and gacha-rolling skins
## against a player profile.
##
## WHY THIS EXISTS SEPARATELY FROM THE SCREEN. Every rule that can lose the player
## points -- affordability, ownership, "is this even buyable", the gacha's duplicate
## refund -- lives here rather than in [CollectionScreen], so the rules are testable
## without building a Control, and so the screen only ever renders the outcome.
##
## PROFILE IS INJECTED AND DUCK-TYPED. The profile object is whatever the caller
## passes (the PlayerProfile autoload in game, a mock in tests). Every call is
## guarded with has_method(), so a MISSING profile degrades to a read-only shop --
## zero points, nothing owned, every write a no-op -- instead of crashing. That is
## deliberate: the Collection screen must still open (and read as empty) if the
## profile autoload is not registered.
##
## RNG. The gacha uses an INJECTED [RandomNumberGenerator] that the caller seeds
## however it likes (the screen randomizes a fresh local one). This is a COSMETIC,
## CLIENT-LOCAL generator and is emphatically NOT the deterministic match RNG -- a
## skin roll must never touch the stream that networked peers replay.

## Points a single gacha roll costs.
const GACHA_COST: int = 250

## Outcome reason codes (a failed call reports one; "" means success).
const REASON_NONE: String = ""
const REASON_NO_PROFILE: String = "no_profile"
const REASON_NO_SKIN: String = "no_skin"
const REASON_ALREADY_OWNED: String = "already_owned"
const REASON_NOT_BUYABLE: String = "not_buyable"
const REASON_NOT_OWNED: String = "not_owned"
const REASON_INSUFFICIENT: String = "insufficient_points"
const REASON_EMPTY_POOL: String = "empty_pool"
const REASON_SPEND_FAILED: String = "spend_failed"

## The injected profile (PlayerProfile autoload, a mock, or null).
var _profile: Object = null


func _init(profile: Object = null) -> void:
	_profile = profile


## Replace the backing profile (tests / late autoload resolution).
func set_profile(profile: Object) -> void:
	_profile = profile


func has_profile() -> bool:
	return _profile != null


# --- Reads -----------------------------------------------------------------

## Spendable balance; 0 when there is no profile.
func points() -> int:
	if not _has("get_points"):
		return 0
	return int(_profile.get_points())


func owns(skin_id: String) -> bool:
	if skin_id.is_empty():
		return true  # "" is the default look -- always available.
	if not _has("owns_skin"):
		return false
	return bool(_profile.owns_skin(skin_id))


## Owned skin ids as an Array (a copy; empty without a profile).
func owned_ids() -> Array:
	if not _has("get_owned_skins"):
		return []
	var owned = _profile.get_owned_skins()
	return owned if owned is Array else []


## The skin equipped on [param character_id], or "" for the default look.
func equipped_for(character_id: String) -> String:
	if character_id.is_empty() or not _has("get_equipped_skin"):
		return ""
	return String(_profile.get_equipped_skin(character_id))


# --- Writes ----------------------------------------------------------------

## Equip [param skin_id] on [param character_id]; pass "" to clear back to the
## default look. Returns false (changing nothing) when there is no profile, the
## character is empty, or the skin is not OWNED -- ownership is re-checked here and
## not trusted from the UI, so a stale card can never equip something unbought.
func equip(character_id: String, skin_id: String) -> bool:
	if character_id.is_empty() or not _has("equip_skin"):
		return false
	if not skin_id.is_empty() and not owns(skin_id):
		return false
	_profile.equip_skin(character_id, skin_id)
	return true


## Buy [param skin] outright with points. Returns
## { "ok": bool, "reason": String, "spent": int }.
## Re-checks, in order: a profile exists, the skin is real, it is not already owned,
## it is buyable at all (a gacha-only skin has price 0 and can NEVER be bought), and
## the balance covers the price. The spend itself goes through the profile, which
## refuses to overdraw -- so the balance is guarded twice.
func buy(skin: SkinResource) -> Dictionary:
	if not _has("spend_points") or not _has("add_skin"):
		return _fail(REASON_NO_PROFILE)
	if skin == null:
		return _fail(REASON_NO_SKIN)
	var skin_id: String = String(skin.id)
	if skin_id.is_empty():
		return _fail(REASON_NO_SKIN)
	if owns(skin_id):
		return _fail(REASON_ALREADY_OWNED)
	if not skin.is_buyable():
		return _fail(REASON_NOT_BUYABLE)
	var price: int = skin.price
	if points() < price:
		return _fail(REASON_INSUFFICIENT)
	if not bool(_profile.spend_points(price, "skin:" + skin_id)):
		return _fail(REASON_SPEND_FAILED)
	_profile.add_skin(skin_id)
	return { "ok": true, "reason": REASON_NONE, "spent": price }


## Roll the gacha with the injected [param rng]. Returns
## { "ok", "reason", "skin_id", "rarity", "is_duplicate", "refund", "spent" }.
##
## DUPLICATE REFUND, NO PITY (v1). A roll that lands an already-owned skin refunds
## [constant SkinLibrary.DUPLICATE_REFUND] points. There is deliberately NO pity
## timer in v1: every roll is independent, so a long dry streak is possible. Adding
## pity later means tracking a counter on the profile -- the pure roll in
## [method SkinLibrary.roll_with_rng] is where it would slot in.
##
## HOW THE REFUND IS PAID. The outcome is decided first (pure), then the NET amount
## (cost, minus the refund on a duplicate) is spent in ONE call. That is
## balance-identical to "spend 250, hand back 100" but needs only spend_points --
## it never depends on a grant/credit entry point, so the profile's public contract
## stays minimal. Affordability is still checked against the FULL cost, so a player
## can never roll on 150 points and get away with it because the result happened to
## be a duplicate.
func roll(rng: RandomNumberGenerator) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": REASON_NO_PROFILE,
		"skin_id": "",
		"rarity": SkinResource.Rarity.COMMON,
		"is_duplicate": false,
		"refund": 0,
		"spent": 0,
	}
	if not _has("spend_points") or not _has("add_skin"):
		return out

	var gen: RandomNumberGenerator = rng
	if gen == null:
		gen = RandomNumberGenerator.new()
		gen.randomize()

	if points() < GACHA_COST:
		out["reason"] = REASON_INSUFFICIENT
		return out

	var result: Dictionary = SkinLibrary.roll_with_rng(gen, owned_ids())
	var skin_id: String = String(result.get("skin_id", ""))
	if skin_id.is_empty():
		# Nothing in the pool: charge nothing.
		out["reason"] = REASON_EMPTY_POOL
		return out

	var refund: int = int(result.get("refund", 0))
	var net: int = maxi(0, GACHA_COST - refund)
	if net > 0 and not bool(_profile.spend_points(net, "gacha:" + skin_id)):
		out["reason"] = REASON_SPEND_FAILED
		return out

	var is_dup: bool = bool(result.get("is_duplicate", false))
	if not is_dup:
		_profile.add_skin(skin_id)

	out["ok"] = true
	out["reason"] = REASON_NONE
	out["skin_id"] = skin_id
	out["rarity"] = int(result.get("rarity", SkinResource.Rarity.COMMON))
	out["is_duplicate"] = is_dup
	out["refund"] = refund
	out["spent"] = net
	return out


## True when the player can afford a roll right now.
func can_roll() -> bool:
	return _has("spend_points") and points() >= GACHA_COST


# --- internals -------------------------------------------------------------

func _has(method_name: String) -> bool:
	return _profile != null and _profile.has_method(method_name)


func _fail(reason: String) -> Dictionary:
	return { "ok": false, "reason": reason, "spent": 0 }
