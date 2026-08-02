# systems/net — Consolidated multiplayer

`NetSession` is the single, server-authoritative multiplayer core for Conquest.
It replaced the older, overlapping stack (`systems/networking/*`,
`systems/multiplayer/*`, `systems/game_core/*NetworkHandler*` — all now deleted)
with one node built directly on Godot's high-level multiplayer API.
`multiplayer_launcher` and `AutoClientDetector` survive as the dev-test
auto-join affordance and run on NetSession like everything else.

## Why this exists

The previous design layered five "manager" classes over a hand-rolled
`Dictionary` message protocol, created its own second `MultiplayerAPI`, hardcoded
two players, and relied on timers/retries to sync join state. It worked as a
2-player demo but does not scale and is hard to reason about.

`NetSession` fixes the fundamentals:

| Concern | Old stack | NetSession |
|---|---|---|
| Authority | host-as-peer, trust-based | **server-authoritative** (validate → broadcast) |
| Transport | custom Dict protocol over 1 RPC | native typed RPCs |
| MultiplayerAPI | a second instance + scene tree's | **one** (scene tree's) |
| Players | hardcoded 0/1 | **N** (`max_players`) |
| Roster sync | player_info request + TODOs | authoritative roster RPC |
| Join flow | `await create_timer(2.0)` guesses | signal-driven |

## Model

```
Client                         Server (authority)
  submit_intent(action) ─────► _rpc_intent
                                  │ validate (well-formed, turn, game rules)
                                  ▼
                         _rpc_apply_action.rpc(resolved)  ──► ALL peers
  action_applied ◄─────────────────────────────────────────  (incl. server)
```

Clients never mutate shared state directly. They submit an **intent**; the
server is the only place that decides whether it's legal, then broadcasts the
**resolved** action to everyone (including itself, via `call_local`). Every peer
mutates its game state in one place: the `action_applied` handler.

## Setup

Add the autoload (already added to `project.godot`):

```
[autoload]
NetSession="*res://systems/net/NetSession.gd"
```

`NetProtocol` is a `class_name` (not an autoload) — available globally.

## Usage

Host (listen server — host is also a player):
```gdscript
NetSession.max_players = 4
NetSession.host_game("Alice", 8910)
```

Join:
```gdscript
NetSession.join_game("203.0.113.5", "Bob", 8910)
NetSession.connection_failed.connect(func(): print("could not connect"))
```

Dedicated (headless) server:
```gdscript
NetSession.start_dedicated_server(8910, 8)  # up to 8 clients, no local player
```

Lobby → match:
```gdscript
NetSession.roster_changed.connect(_refresh_lobby_ui)
NetSession.set_ready(true)
# server decides when everyone's ready:
NetSession.start_match()
```

Gameplay:
```gdscript
# Plug in your rules (server-side only; safe to set on all peers):
NetSession.action_validator = func(action, slot):
    return TurnSystemManager.validate_turn_action_for_slot(action, slot)

NetSession.action_applied.connect(_apply_action)   # mutate game state here
NetSession.turn_changed.connect(func(slot): _hud.set_active(slot))

# Player does something:
var a := NetProtocol.make_action(NetProtocol.Action.MOVE_UNIT, {"unit_id": 12, "to": Vector2i(4, 7)})
NetSession.submit_intent(a)
```

`func _apply_action(action):` should be **deterministic** and identical on every
peer — it's the single source of state change.

## Migration plan (incremental, non-breaking)

1. **Add** `NetSession` alongside the old stack (done). Nothing else changes yet.
2. Point new lobby/game UI (`CollaborativeLobby`, `NetworkMultiplayerSetup`) at
   `NetSession` host/join + `roster_changed`. **(done)** — the Host and Connect
   buttons call `host_game` / `join_game` directly, the connect state machine is
   driven by `roster_changed` / `connection_failed` / `disconnected` /
   `join_rejected`, and the lobby's votes/ready/game-start ride
   [`send_lobby_message`](#lobby-channel).
3. Route unit move/attack/end-turn through `submit_intent` / `action_applied`
   instead of `MultiplayerManager.submit_game_action`. **(done)** — see
   `UnitActionsPanel._is_networked_match()`.
4. Move rule checks into `action_validator`.
5. Delete `systems/networking/`, `systems/multiplayer/` and
   `game_core/*NetworkHandler*` — the Dictionary-based state simulator and every
   class that existed to wire it. **(done)** — along with the `dev_scripts/`
   harnesses that drove them.
   `multiplayer_launcher.gd` and `AutoClientDetector.gd` are **kept on purpose**:
   they are the two-instances-on-one-machine dev-test affordance, and both now
   drive `NetworkMultiplayerSetup.begin_auto_join()`, i.e. NetSession over
   localhost ENet — the same transport a real two-machine match uses.
   `GameModeManager` is also kept, reduced to the local (solo / hot-seat) session
   plus the `submit_action` / `get_game_status` surface the lobby falls back to.

## Lobby channel

Pre-match traffic (map votes, ready flags, the game-start MatchSettings payload)
is **not** part of the gameplay command vocabulary — it is never validated,
sequenced or RNG-stamped, and must never mutate battle state:

```gdscript
NetSession.lobby_message.connect(_on_lobby_message)   # (type, data, from_slot)
NetSession.send_lobby_message("map_vote", { "map_path": path })
```

The server relays; **the sender never receives its own message back**, so a lobby
UI can broadcast unconditionally. Treat `data` as untrusted peer input.
`CollaborativeLobby` picks this channel whenever `is_connected_session()` is true
and falls back to the legacy `GameModeManager.submit_action` envelope otherwise.

## What the player sees at the seam

Two things the seam owes the player, both wired at the point a command is **applied or
refused** rather than where it is submitted:

- **Refused commands are surfaced.** `_validate_intent` answers with one of the
  `NetProtocol.INTENT_*` wire strings; the origin peer gets it on `intent_rejected`, and
  the battle HUD's `NetToast` renders
  `NetProtocol.describe_intent_rejection(reason, action)` — "Attack rejected — not your
  turn" — as a click-through amber banner that dismisses itself after ~2.5s. Before this
  a refused command was completely silent. Pinned by `tests/unit/test_net_intent_rejection.gd`
  (the wording, pure) and `tests/integration/test_net_rejection_toast.gd` (the wiring).
- **Ultimates flash on every peer.** `CommandApplier._announce_ultimate_cast` emits
  `GameEvents.ultimate_casting` when the applied CAST_MOVE is an ultimate, so a REMOTE
  opponent's ultimate plays the `UltimateCutIn` here too. `UnitActionsPanel` deliberately
  does *not* play it on its networked submit branch, so the local caster flashes exactly
  once — and never for a cast the server then refuses. Pinned by
  `tests/unit/test_command_applier_ultimate.gd`.

## Match settings: whose squad is whose

A `player_id` on a map is a **roster slot**, and the same slot must field the same characters
on both machines. Exactly one participant's Character Select pick is authoritative for each
slot, and `MapLoader.resolve_player_squad(player_id, local_squad, replicated_squad, local_slot,
networked)` is the one rule that says which:

| | `player_id == local_slot` | any other `player_id` |
|---|---|---|
| **not networked** | the local pick (player 0 only) | the map's authored roster |
| **networked** | the local pick | that slot's **replicated** pick |

`resolve_player0_squad(local, host, slot, networked)` is still there — it is the same call with
`player_id = 0` — because slot 0 has its own replication channel: the host's `game_start`
payload carries `host_squad`, the roster for the host's side of the board on *every* peer.
Every **other** slot's pick rides its own `match_loadout` card (below), which is the client →
host twin `game_start` never had. Before that a client's pick reached nobody and player 1
fielded the map's authored roster on both peers; before `host_squad` was *applied*, a client
fed its OWN pick into player 0's slots and the boards disagreed on the first frame.

Both squads are untrusted peer input, so ids are normalised at the boundary
(`MapLoader.normalise_squad_ids` for shape, `MatchLoadouts.normalise_squad` for shape *and* a
`CharacterLibrary` whitelist — `MapLoader` falls back to a default character for an id it
cannot resolve, so an unchecked junk id would become a real unit rather than cost its slot).
An empty or absent squad means "field the map's authored roster for that slot" on **both**
peers, which is also what that participant's own empty pick does — so they still agree.

A squad-picked spawn is exempt from the `min_difficulty` gate on *any* slot, not just player 0:
`ai_difficulty` is a local setting, so gating a human opponent's replicated pick would drop the
unit on one peer and keep it on the other.

Pinned by `tests/integration/test_net_host_squad.gd` (slot 0) and
`tests/integration/test_net_client_squad.gd` (slot 1, both roles).

## Squad, loadouts and skins: `match_loadout`

A participant's squad decides which units exist at all; equipped items are real buffs (+Max HP,
regen, a damage-reduction ward) and skins change what a unit looks like — and all three live in
process-local storage (`GameSettings.selected_squad`, `ItemInventory`, the `PlayerProfile`
autoload). So **both** machines need **both** sides' data before a single unit spawns.
`game_start` is host → client only and has no twin, so this is its own bidirectional lobby
message, in the shape `profile_info`/`MatchPeerInfo` already uses:

```gdscript
NetSession.send_lobby_message("match_loadout", {
    "squad":    ["<character_id>"],                   # this peer's pick, in order, MAX_SQUAD max
    "equipped": { "<character_id>": "<item_id>" },   # UNIT-scope items, per character
    "team":     ["<item_id>"],                        # TEAM slots, ItemInventory.TEAM_SLOTS max
    "skins":    { "<character_id>": "<skin_id>" },    # cosmetic skin per character
})
```

`CollaborativeLobby` sends exactly one card per peer, at the two moments the profile card is
exchanged (host: on admitting the opponent; client: alongside its `lobby_hello`). Cards are
parked in `MatchLoadouts`, keyed by the **server-stamped** sender slot, and survive the scene
change into the battle. The same announcement records `MatchLoadouts.set_local_slot()`, which
is the flag that switches replication on — every solo / hotseat / arena path leaves it unset
and reads `is_active()` as false, so those are untouched.

At spawn, `MapLoader` fills a remote slot's START points from `MatchLoadouts.squad_for(slot)`
and `ItemSystem` equips *every* human slot: our own from the local inventory, a remote slot
from its card — both through the one shared `ItemSystem.apply_loadout_items()`, so the two
simulations compute identical stats. `Unit.apply_equipped_skin` asks
`MatchLoadouts.skin_for(slot, character_id, profile)` for the same reason.

**Staleness.** `MatchLoadouts` (and `GameSettings.host_squad`) are process-wide and outlive the
scene change, so they are cleared at *both* ends: `CollaborativeLobby.initialize` when a new
networked lobby forms, and `MapLoader._clear_stale_replication` when a battle that is **not** a
live networked match builds its board. Without the second, lobby → versus → Main Menu → a solo
battle never passes a lobby again and would read the previous opponent's card.

**Trust:** the payload is untrusted peer input and there is no server-side ownership proof.
`MatchLoadouts.normalise()` is the floor: a squad id must resolve in `CharacterLibrary`, an
item id must resolve in `ItemLibrary` *and* carry the scope it was announced for, a skin id
must resolve in `SkinLibrary` *and* be authored for the character it was announced against,
ids are length-capped, the squad is capped at `MAX_SQUAD` and both maps entry-capped.
Anything else is dropped, so a hostile peer can only ever field fewer buffs than it claimed.
An ownership proof is the natural next step and slots in here. Pinned by
`tests/unit/test_match_loadouts.gd` and `tests/unit/test_lobby_loadout_exchange.gd`.

## Join handshake (the build gate)

A joining client's **first** message is a hello — display name plus
`NetProtocol.PROTOCOL_VERSION` and `application/config/version` — sent from
`_on_connected_to_server`. The server runs the pure
`NetProtocol.validate_hello()` **before** the peer gets a roster slot:

- different `PROTOCOL_VERSION` → `_rpc_join_rejected` with reason
  `version_mismatch`, then the peer is dropped. The client emits
  `join_rejected(reason, info)`; `NetProtocol.describe_rejection()` turns that
  into the line a menu shows.
- same protocol, different game version → admitted, `build_differs` logged
  (an editor run joining an exported build is a legitimate test setup).

Bump `PROTOCOL_VERSION` whenever the envelope or a command's data shape changes.
Pinned by `tests/unit/test_net_handshake.gd`; the two-machine procedure is
`docs/NETWORK_TESTING.md`.

## Scaling beyond a few players

- The listen-server model handles small matches. For larger/public play, run
  `start_dedicated_server()` as a headless build; clients use `join_game`.
- `_rpc_apply_action` is reliable+ordered. For high-frequency state (positions
  mid-animation) add a separate `unreliable_ordered` channel; keep authoritative
  actions reliable.
- The roster is a plain dictionary; a matchmaking front-end can create one
  dedicated-server process per match and hand clients its address.

## Tests

See `tests/unit/test_net_protocol.gd`. `NetSession` itself needs two live peers,
so exercise it with a headless host + client (or Godot's built-in debug
multiplayer) rather than a pure unit test.
