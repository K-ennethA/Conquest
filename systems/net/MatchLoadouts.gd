class_name MatchLoadouts
extends RefCounted

## PROCESS-WIDE holder for the SQUAD, ITEM LOADOUTS and COSMETIC SKINS every participant of a
## networked match announced about itself in the lobby (the "match_loadout" message).
##
## WHY THIS EXISTS: items are real buffs -- +5 Max HP, regen, a damage-reduction ward -- and
## skins change what a unit LOOKS like. Both live in process-local storage ([ItemInventory],
## the PlayerProfile autoload), so without replication each machine would apply only its OWN
## equips to slot 0 and the two peers would simulate different stats and render different
## units. [ItemSystem] used to sidestep that by refusing to equip anything at all in a
## networked match; this holder is what lets it stop doing that.
##
## THE SQUAD rides the same card for the same reason, one level earlier: WHICH characters a
## participant fields is also a purely local Character Select pick. The host's is replicated
## separately (the game_start payload's "host_squad", which names slot 0 on every peer), but
## that message is host -> client only, so a CLIENT's pick reached nobody and player 1 fell
## back to the map's authored roster on both machines. This card is the client -> host twin
## that closes it: every peer announces its own squad, keyed by its own slot, and
## [method MapLoader.resolve_player_squad] fills that slot's START points with it on BOTH
## machines.
##
## WHY IT RIDES THE LOBBY: both sides need the OTHER side's data BEFORE any unit spawns, and
## the lobby is the only place where both peers are talking while nothing is on the board yet.
## The exchange therefore follows the exact shape [MatchPeerInfo]'s "profile_info" already
## uses -- announced by BOTH sides while the lobby forms, parked here, read by the battle --
## rather than widening the host-only game_start payload, which has no client -> host twin.
##
## TRUST: every stored card came off the wire as an UNTRUSTED peer Dictionary (see
## [method NetSession.send_lobby_message]). [method set_peer_loadout] therefore WHITELISTS it:
## an item id must resolve in [ItemLibrary] AND sit in the scope it was announced for, a skin
## id must resolve in [SkinLibrary] AND be authored for the character it was announced against,
## a squad id must resolve in [CharacterLibrary] (and the squad is capped at
## [constant MAX_SQUAD]), and both maps are capped at [constant MAX_ENTRIES]. Anything else is
## dropped, so a hostile
## or buggy peer can only ever field FEWER buffs than it claimed, never a fabricated one and
## never a crash. There is no server-side ownership check (nothing on the wire proves the
## sender really owns what it equipped) -- the library whitelist is deliberately the floor,
## and the place a future ownership proof would slot in.
##
## LIFECYCLE: [method clear] runs at BOTH ends -- when a new lobby initialises ([method
## CollaborativeLobby.initialize]), exactly like [method MatchPeerInfo.clear], and when a battle
## that is NOT a live networked match builds its board ([method MapLoader._clear_stale_replication]).
## The first stops one match's loadouts being applied in the next; the second stops them being
## applied in a solo / campaign / challenge battle launched afterwards without passing through a
## lobby again. [member _local_slot] is what makes the holder
## ACTIVE: it is only ever set from a live networked lobby, so every solo / hotseat / arena
## path reads [method is_active] as false and keeps its existing behaviour untouched.

## Longest peer-supplied id (item, skin or character) that will even be considered.
const MAX_ID_LENGTH: int = 64

## Most character entries a single card may carry, in either map. The roster is far smaller
## than this; the cap exists so a peer cannot hand us a million-key dictionary.
const MAX_ENTRIES: int = 128

## Most character ids a peer's announced SQUAD may carry. Character Select allows at most one
## pick per player-0 START point on the map; this ceiling is far above any shipped map, and
## exists so a peer cannot hand us an unbounded roster.
const MAX_SQUAD: int = 32

## slot (int) -> { "equipped": Dictionary, "team": Array[String], "skins": Dictionary,
## "squad": Array[String] }. Static so it survives the scene change from the lobby into the
## battle.
static var _peers: Dictionary = {}

## This peer's own roster slot for the current networked match, or -1 when there is none.
## Doubles as the "replication is in force" flag -- see [method is_active].
static var _local_slot: int = -1


# --- Local slot / lifecycle -------------------------------------------------

## Record which roster slot THIS machine plays. Called by the lobby from a live networked
## session (NetSession.local_slot()); a negative value switches replication back off.
static func set_local_slot(slot: int) -> void:
	_local_slot = int(slot) if int(slot) >= 0 else -1


## The slot this machine plays, or -1 outside a networked match.
static func local_slot() -> int:
	return _local_slot


## True when loadout/skin replication is in force for the current match. False in every solo,
## hotseat, campaign, challenge and arena path -- which is what keeps those unchanged.
static func is_active() -> bool:
	return _local_slot >= 0


## Forget every recorded card AND the local slot. Called when a new lobby initialises so one
## match's loadouts can never leak into the next (and so a solo battle started after a
## networked one reads as inactive).
static func clear() -> void:
	_peers.clear()
	_local_slot = -1


# --- The wire card ----------------------------------------------------------

## Build THIS machine's card: which characters the local player fields, what they have
## equipped and which skins they wear.
##
## [param profile] is the skin source, duck-typed and injected (the PlayerProfile autoload in
## game, a stand-in in tests, null in a headless harness -- which simply yields no skins).
## Items come from [ItemInventory], which is static and always available. [param squad] is the
## local Character Select pick (GameSettings.selected_squad), injected the same way rather than
## read off an autoload, so this stays a pure function of what it is handed. An EMPTY squad is
## announced as empty and means "field the map's authored roster for my slot" -- the same thing
## an empty host_squad already means for slot 0.
##
## Only ids the LOCAL libraries know are ever put on the wire, so the receiving side's
## whitelist has nothing to reject in the honest case.
static func build_local_payload(profile: Object = null, squad: Array = []) -> Dictionary:
	var equipped: Dictionary = {}
	var local_equipped: Dictionary = ItemInventory.equipped_map()
	for character_key in local_equipped.keys():
		var item_id: String = String(local_equipped[character_key])
		if ItemLibrary.has_item(item_id):
			equipped[String(character_key)] = item_id

	var team: Array[String] = []
	for item_id in ItemInventory.team_items():
		if ItemLibrary.has_item(item_id):
			team.append(String(item_id))

	return {
		"equipped": equipped,
		"team": team,
		"skins": _local_skin_map(profile),
		"squad": normalise_squad(squad),
	}


## Record (or replace) the card [param data] announced by the participant in [param slot],
## NORMALISED (see the TRUST note above). A negative slot is still accepted -- the server
## stamps -1 when a sender had no seat yet -- so a very early announcement is not lost.
static func set_peer_loadout(slot: int, data: Dictionary) -> void:
	_peers[int(slot)] = normalise(data)


## The card recorded for [param slot], or an EMPTY card when that peer never announced one.
## Returns a COPY: a caller mutating the result must not edit the stored record.
static func get_peer_loadout(slot: int) -> Dictionary:
	var stored: Variant = _peers.get(int(slot), null)
	if not (stored is Dictionary):
		return _blank()
	return (stored as Dictionary).duplicate(true)


## True when [param slot] announced a card (even an empty one -- "I equipped nothing" is an
## answer, and it is what stops [ItemSystem] applying the LOCAL player's items to a peer).
static func has_peer_loadout(slot: int) -> bool:
	return _peers.has(int(slot))


## How many peers have announced a card.
static func peer_count() -> int:
	return _peers.size()


# --- Reads the battle uses --------------------------------------------------

## The character ids the participant in [param slot] announced it would field, in pick order,
## already whitelisted against [CharacterLibrary]. EMPTY when that slot never announced a card,
## or announced no squad -- which means "field the map's authored roster for that slot", the
## same fallback an absent host_squad has always had.
##
## Read by [method MapLoader.resolve_player_squad] to fill a REMOTE participant's START points.
## Our own slot never comes through here: the local Character Select pick is authoritative for
## us on our own machine, exactly as it is for our items and skins.
static func squad_for(slot: int) -> Array[String]:
	var out: Array[String] = []
	for id in (get_peer_loadout(int(slot))["squad"] as Array):
		out.append(String(id))
	return out


## The item ids [param slot] has in force for [param character_id]: its worn UNIT item (when
## it has one) followed by every filled TEAM slot -- the same ordering
## [method ItemSystem.loadout_for] produces from the local inventory, so the two sides build
## the identical list. Empty for a slot that never announced.
static func item_ids_for(slot: int, character_id: String) -> Array[String]:
	var out: Array[String] = []
	var card: Dictionary = get_peer_loadout(slot)
	var worn: String = String((card["equipped"] as Dictionary).get(String(character_id).strip_edges(), ""))
	if not worn.is_empty():
		out.append(worn)
	for item_id in (card["team"] as Array):
		out.append(String(item_id))
	return out


## [method item_ids_for], resolved against the LOCAL [ItemLibrary]. Ids are re-checked here as
## well as at the boundary, so a content edit between the announcement and the battle drops the
## item rather than handing [ItemSystem] a null.
static func items_for(slot: int, character_id: String) -> Array[ItemResource]:
	var out: Array[ItemResource] = []
	for item_id in item_ids_for(slot, character_id):
		var item: ItemResource = ItemLibrary.get_item(item_id)
		if item != null:
			out.append(item)
	return out


## The skin id the owner of [param slot] wears on [param character_id], or "" for the default
## look. THE one policy call for "which skin does this unit wear", used by [Unit]:
##
##   * replication OFF (solo / hotseat / campaign / challenge / arena): only slot 0, the local
##     human, wears skins, read from the local [param profile]. Exactly the pre-existing rule.
##   * replication ON (networked): the LOCAL slot still reads the local profile; every other
##     slot reads its announced (and already whitelisted) card.
static func skin_for(slot: int, character_id: String, profile: Object = null) -> String:
	var character_key: String = String(character_id).strip_edges()
	if character_key.is_empty():
		return ""
	if is_active():
		if int(slot) == _local_slot:
			return _profile_skin(profile, character_key)
		return String((get_peer_loadout(int(slot))["skins"] as Dictionary).get(character_key, ""))
	if int(slot) != 0:
		return ""
	return _profile_skin(profile, character_key)


# --- Normalisation (the trust boundary) -------------------------------------

## Coerce an untrusted payload into the fixed three-field card every reader expects, dropping
## everything that does not survive the whitelist. Public so a test can drive the boundary
## directly, and so the shape is documented in one place.
static func normalise(data: Dictionary) -> Dictionary:
	var out: Dictionary = _blank()

	var equipped_raw: Variant = data.get("equipped", {})
	if equipped_raw is Dictionary:
		var equipped: Dictionary = out["equipped"]
		for key in (equipped_raw as Dictionary).keys():
			if equipped.size() >= MAX_ENTRIES:
				break
			var character_key: String = _clean_id(key)
			if character_key.is_empty() or equipped.has(character_key):
				continue
			var item_id: String = _whitelisted_item(equipped_raw[key], ItemResource.Scope.UNIT)
			if not item_id.is_empty():
				equipped[character_key] = item_id

	var team_raw: Variant = data.get("team", [])
	if team_raw is Array:
		var team: Array[String] = out["team"]
		for entry in (team_raw as Array):
			if team.size() >= ItemInventory.TEAM_SLOTS:
				break
			var item_id: String = _whitelisted_item(entry, ItemResource.Scope.TEAM)
			if not item_id.is_empty():
				team.append(item_id)

	var skins_raw: Variant = data.get("skins", {})
	if skins_raw is Dictionary:
		var skins: Dictionary = out["skins"]
		for key in (skins_raw as Dictionary).keys():
			if skins.size() >= MAX_ENTRIES:
				break
			var character_key: String = _clean_id(key)
			if character_key.is_empty() or skins.has(character_key):
				continue
			var skin_id: String = _whitelisted_skin(skins_raw[key], character_key)
			if not skin_id.is_empty():
				skins[character_key] = skin_id

	out["squad"] = normalise_squad(data.get("squad", []))

	return out


## Coerce an untrusted squad list into plain character ids: scalar ids only, trimmed,
## length-capped, each one resolving in [CharacterLibrary], at most [constant MAX_SQUAD] of
## them. DUPLICATES ARE KEPT -- fielding two vineweaves is a legal pick, so unlike the
## per-character maps above this list is not deduplicated, and ORDER is preserved because it
## is what decides which START point each pick lands on.
##
## The roster check matters because [MapLoader] falls back to its DEFAULT_CHARACTER_ID for an
## id it cannot resolve: without the whitelist a junk id off the wire would silently become a
## real unit on the board instead of costing the slot it named.
static func normalise_squad(raw) -> Array[String]:
	var out: Array[String] = []
	if not (raw is Array):
		return out
	for entry in (raw as Array):
		if out.size() >= MAX_SQUAD:
			break
		var character_id: String = _clean_id(entry)
		if character_id.is_empty():
			continue
		if CharacterLibrary.get_character(character_id) == null:
			continue
		out.append(character_id)
	return out


# --- internals --------------------------------------------------------------

## An empty card. Every reader can index all four fields without a has() check.
static func _blank() -> Dictionary:
	var team: Array[String] = []
	var squad: Array[String] = []
	return { "equipped": {}, "team": team, "skins": {}, "squad": squad }


## Coerce an untrusted key/value to a usable id String: strings only (a Dictionary or Array
## key is nonsense here), trimmed, and length-capped. "" means "reject".
static func _clean_id(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			var text: String = String(value).strip_edges()
			return text if text.length() <= MAX_ID_LENGTH else ""
		_:
			return ""


## [param value] as an item id, but ONLY when it resolves in the local [ItemLibrary] and the
## resolved item really carries [param scope]. The scope check is what stops a peer announcing
## a UNIT item in all its TEAM slots (or vice versa) to multiply a bonus the local rules would
## never let it hold.
static func _whitelisted_item(value: Variant, scope: int) -> String:
	var item_id: String = _clean_id(value)
	if item_id.is_empty():
		return ""
	var item: ItemResource = ItemLibrary.get_item(item_id)
	if item == null or int(item.scope) != scope:
		return ""
	return item_id


## [param value] as a skin id, but ONLY when it resolves in the local [SkinLibrary] and is
## authored for [param character_key]. The character check mirrors what [Unit] already does
## before tinting, so a peer cannot dress its Vineweave in a Blightcap skin.
static func _whitelisted_skin(value: Variant, character_key: String) -> String:
	var skin_id: String = _clean_id(value)
	if skin_id.is_empty():
		return ""
	var skin: SkinResource = SkinLibrary.find(skin_id)
	if skin == null or String(skin.character_id) != character_key:
		return ""
	return skin_id


## Every roster character's equipped skin, read one id at a time through the profile's public
## accessor (there is no "give me the whole map" call, and iterating [CharacterLibrary] also
## keeps unknown character ids off the wire).
static func _local_skin_map(profile: Object) -> Dictionary:
	var out: Dictionary = {}
	if profile == null or not profile.has_method("get_equipped_skin"):
		return out
	for character_id in CharacterLibrary.all_ids():
		var character_key: String = String(character_id)
		if character_key.is_empty():
			continue
		var skin_id: String = String(profile.get_equipped_skin(character_key)).strip_edges()
		if skin_id.is_empty():
			continue
		var skin: SkinResource = SkinLibrary.find(skin_id)
		if skin != null and String(skin.character_id) == character_key:
			out[character_key] = skin_id
	return out


## The local profile's equipped skin for [param character_key]. Duck-typed and null-safe: a
## missing profile (headless, tests, a load-order shift) is the default look, never a crash.
static func _profile_skin(profile: Object, character_key: String) -> String:
	if profile == null or not profile.has_method("get_equipped_skin"):
		return ""
	return String(profile.get_equipped_skin(character_key))
