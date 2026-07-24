# systems/net — Consolidated multiplayer

`NetSession` is the single, server-authoritative multiplayer core for Conquest.
It replaces the older, overlapping stack (`systems/networking/*`,
`systems/multiplayer/*`, `systems/game_core/*NetworkHandler*`, `multiplayer_launcher`,
`AutoClientDetector`) with one node built directly on Godot's high-level
multiplayer API.

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
   `NetSession` host/join + `roster_changed`.
3. Route unit move/attack/end-turn through `submit_intent` / `action_applied`
   instead of `MultiplayerManager.submit_game_action`.
4. Move rule checks into `action_validator`.
5. Delete `systems/networking/`, `systems/multiplayer/`,
   `game_core/*NetworkHandler*`, `multiplayer_launcher.gd`,
   `AutoClientDetector.gd`, and the root `*client*`/`*detector*` scripts once
   nothing references them.

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
