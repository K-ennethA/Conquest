# systems/net — Network multiplayer

Network versus is built on ONE stack: Godot's scene-tree `multiplayer` API,
host-authoritative, 1v1, over a pluggable transport (ENet by default). The
host is either a **player** (listen server, seat 0) or a **dedicated headless
server** with no seat. Combat randomness is **commit-reveal**: no peer — the
host included — can know or bias a roll before the action that consumes it is
irrevocably accepted.

## Pieces

| File | Role |
|---|---|
| `NetSession.gd` (class `NetSessionNode`, autoload `NetSession`) | Lobby, peer→slot seating, intent queue, action ordering (seq), the commit-reveal rounds, checkpoints, disconnects. Player-hosted (`host_game`) and dedicated (`host_dedicated`) modes share every code path. Knows nothing about units. |
| `NetCommitReveal.gd` | Hash-chain commitments, share verification, epoch re-commit, per-action seed derivation. Pure (no networking), unit-tested. |
| `transport/NetTransport.gd`, `transport/ENetTransport.gd` | The only place a `MultiplayerPeer` is created. See *Adding a transport*. |
| `NetProtocol.gd` | Wire format: action types (`MOVE`, `USE_MOVE`, `WAIT`, `END_TURN`), builders, shape validation, THE cell (de)serialiser (`[col, row, floor]`, see docs/MULTI_FLOOR.md), `KEY_RNG` (locally stamped seed, never trusted from the wire). |
| `NetGameRules.gd` | Host-side `validate_intent` (also re-run by clients) and the ONE deterministic `apply_action` every peer runs; `state_digest` for desync detection. |
| `NetUnitIds.gd` | Stable unit ids (`"<slot>:<n>"`, mid-match spawns `"<slot>:s<k>"`). |
| `DedicatedServer.gd` | Headless server driver: args, lobby, match lifecycle, sequential matches, logs. |
| `systems/game_core/GameModeManager.gd` (autoload) | Live-game glue (match config → `GameSettings`, battle load, rules attach, `request_*` intents, disconnect / desync / cheat → menu message) and command-line boot of `--server` / `--net-bot`. |
| `menus/NetworkMultiplayerSetup.gd` | Host / join by address:port (a friend's game or a dedicated server) and the lobby. |
| `dev_scripts/net_bot_client.gd`, `dev_scripts/net_multiprocess_check.sh` | Scripted headless client + the 3-process check (see *Testing*). |

## Flow

```
Lobby    host_game(name, port)  |  host_dedicated(port, cfg, rng_mode)  |  join_game(addr, name, port)
         host seats peers (max 2; extras get join_rejected("lobby_full"),
         late joiners "match_in_progress"); set_ready; config by the player-host,
         or on a dedicated server by --map/--turn-system (locked) or the slot-0
         client (lobby leader). start_match(): full + all ready, single-shot
         (a dedicated server auto-starts).

Commit   host: fresh secret chain, broadcast (contributors, chain length, host anchor)
         each contributing client: fresh chain -> its anchor -> host
         host: all anchors in -> match_started {map, turn system, slots,
               anchors, seed = setup seed derived from the anchors}
         clients check their own + the host's anchor are the ones committed.

Match    UI --request_*--> submit_intent --rpc--> host intent queue
         host (one intent at a time, only when no RNG round is in flight):
             validate_intent(action, sender's seat) -> rejected: intent_rejected
             accepted -> stamp {actor, seq}; broadcast ACCEPTED(action, host share)
         clients: verify the host share against the host chain; check an action
             in their own seat is the intent they sent; THEN reveal their share
         host: verify each share, relay ROUND(seq, shares) to everyone
         every peer: verify, seed = H(shares || seq), apply_action (<= 1 per frame;
             clients first re-validate it on their own state)
         host, next frame: checkpoint {seq, turn slot, digest} -> clients compare.
```

* **Actor is the sender's seat**, never a field of the payload.
* **Apply uses the local-play primitives** (`board.move_unit` + `GameEvents.unit_moved`
  + `mark_moved`; `Unit.perform_move`; `mark_unit_acted`; `end_turn_manually`).
  Hotseat / single-player keep their direct paths.
* **Turns** are derived: every peer runs the same turn system over the same
  applied actions; the host's checkpoint carries the authoritative active slot.
* **Disconnects**: a seat dropping mid-match → `match_aborted("opponent_disconnected")`
  on the host and on the remaining client. A player-host returns to the menu; a
  dedicated server returns to an empty lobby for the next pair.

## Unpredictable, unriggable combat RNG (commit-reveal)

Previously the host picked one match seed and sent it to both players, so a
modified client could predict every hit/crit before choosing an action, and the
host could grind seeds. Now:

**Contributors.** The host / server and (default) every seated client. On a
dedicated server `--rng server` makes the server the only contributor (it is
trusted anyway; fewer round trips); a player-host can never be the only one.

**Chains.** Each contributor draws a secret 32-byte `S` (`Crypto.generate_random_bytes`)
and builds `h_0 = S, h_{i+1} = sha256(h_i)` up to `h_N` (`N = 4096`,
`NetSession.rng_chain_length`). It publishes only the **anchor** `h_N` before the
match. Its share for the k-th action of the epoch is `h_{N-k}`; anyone verifies
it with `sha256(h_{N-k}) == h_{N-k+1}` (the previous verified value). SHA-256 is
one-way, so revealed values say nothing about the next ones, and the whole
future sequence is fixed at commit time.

**Seed.** `seed(seq) = first 8 bytes of sha256(share_c1 || share_c2 || ... || seq)`
(contributors in peer-id order). The action's `RandomNumberGenerator` is seeded
with it, passed to the executor and installed as `CombatServices.match_rng`,
where it **stays until the next action** — so abilities, status ticks, tile
effects and the turn-start ticks deferred after an END_TURN / last WAIT all draw
from the same verified stream. Every action consumes one share per contributor
(also MOVE / WAIT / END_TURN: a WAIT can end the turn and trigger rolling ticks,
and a uniform rule keeps the chains in lockstep; cost ≈ 32 bytes per contributor
per action). Rolls made while the battle is set up, before action 1, use the
public setup seed derived from the anchors.

**Ordering (why nobody can predict).** The host reveals its share only inside the
ACCEPTED broadcast, and clients reveal theirs only after receiving it — so every
share for an action appears after that action is irrevocable:

| Actor | What it knows when choosing | Missing until after acceptance |
|---|---|---|
| player-host | its own chain | the client's share |
| client (player-hosted) | its own chain | the host's share |
| client (dedicated, `rng all`) | its own chain | server's AND the other client's share |
| dedicated server | its own chain | both clients' shares (it does not act anyway) |

The host cannot reject an action after seeing its roll: acceptance is broadcast
before any other share exists. Nobody can bias a roll: chains are committed
before the match and each share must extend its chain. **Epochs:** the last
share of a chain carries the anchor of the contributor's next chain (committed
before any of its values is revealed), so matches can run past `N` actions.

**Verification failure = cheating.** A share that does not extend its chain,
arrives out of order, changes a commitment, or is withheld longer than
`reveal_timeout_ms` (30 s) ends the match: the host / server emits
`cheat_detected` + `match_aborted("rng_verification_failed" | "reveal_timeout")`
and tells the clients; a client that catches the host leaves with
`match_aborted("host_verification_failed")`. The UI shows a clear message.

**Residuals.** The last contributor to reveal learns the roll a moment before
the others and could disconnect instead of revealing (a rage-quit, handled as a
forfeit/abort, never a re-roll). The setup seed (only rolls before the first
action) is derived from the anchors, so the last committer could grind it --
this only affects rolls made while the battle is set up (e.g. a turn-1 start
tick of a map-authored tile effect), never a player-chosen action.

## Trust model

| | Player-hosted (listen server) | Dedicated server |
|---|---|---|
| Who validates | host (a player) — clients re-validate every accepted action on their own state and refuse illegal ones | server — clients re-validate too |
| Actions in your seat | only ones you submitted (host cannot puppet your units: forged → match ends) | same; the server derives the actor from the sending seat |
| Roll prediction | impossible for either player (both contribute) | impossible for clients; the server could only learn rolls post-accept |
| Roll biasing | impossible (committed chains) | impossible for clients; `rng server` mode trusts the server |
| Host-private info | host sees everything a client sends (no hidden info in this game yet) | server sees everything |
| State divergence | per-action digest checkpoint → `desync_detected` → match ends | same |
| Remaining trust | the host process can still refuse / delay your intents, drop you, or run modified rules on ITS copy (you'd see a desync, not a silent change); ENet is unencrypted | operator runs the server; same transport caveat |

There is no hidden information today (both players see the whole board). If
fog of war is added, a player-host sees everything by construction — only a
dedicated server can keep secrets.

## Dedicated server

Run locally (project root, after `godot --headless --import .`):

```
godot --headless --path . -- --server --port 8910 \
      [--map res://game/maps/resources/default_skirmish.tres] \
      [--turn-system traditional|speed_first] [--rng all|server] \
      [--max-matches N] [--end-after-actions N] [--reveal-timeout 30] [--transport enet]
```

`--server` is detected by `GameModeManager` (also any export with the
`dedicated_server` feature tag, i.e. Godot's *Dedicated Server* export mode).
The main menu is unloaded; each match loads the normal `GameWorld` under the
headless dummy renderer (no window, nothing drawn), so the server applies
actions with exactly the systems players run (tile effects, turn ticks, win
conditions). Clients join with the normal **Join** button (address:port): the
roster shows the two players, no host seat. **Lobby leader:** with `--map` the
config is locked; without it the slot-0 client picks map / turn system (the
server sanitises it). The match starts when both are ready. When it is decided
(or a seat drops / cheats) the server tells the clients, drops them, unloads
the battle and reopens the lobby; `--max-matches N` exits after N. Logs:
`[server] ...` lines incl. `FINAL match=… seq=… digest=…` and a heartbeat.

**Many matches per process** is not supported by the live path: PlayerManager,
TurnSystemManager, CombatServices (board, `match_rng`), GameSettings and the
NetSession autoload are singletons, and tile-effect wiring lives in
GameWorldManager. The network core already runs N instances per process (the
tests run three NetSessions + three rule sets over three BoardAdapters in one
SceneTree, each with its own `MultiplayerAPI` branch via `set_multiplayer`). To
host many matches per process: move per-match state into a match context
(board, turn system, players, rng, tile-effect system) instead of autoloads,
give each match a subtree with its own `SceneMultiplayer` and port (or one
listener that routes peers to matches). Until then: **one process per match**,
scaled by an orchestrator (below).

## Adding a transport

`NetSession.transport` is a `NetTransport`; it only has to return a ready
`MultiplayerPeer` from `create_host(port, max_clients)` / `create_client(address,
port)` (null + `last_error` on failure). Everything else (RPCs, seating,
commit-reveal) is transport-agnostic.

1. `systems/net/transport/SteamTransport.gd` (GodotSteam, when the dependency is
   added; sketch -- method names per GodotSteam 4.x, check the installed version):
   ```gdscript
   extends NetTransport
   func id() -> String: return "steam"
   func create_host(_port: int, max_clients: int) -> MultiplayerPeer:
       var p = SteamMultiplayerPeer.new()
       last_error = p.create_host(0)              # virtual port; lobby via Steam.createLobby
       return p if last_error == OK else null
   func create_client(address: String, _port: int) -> MultiplayerPeer:
       var p = SteamMultiplayerPeer.new()
       last_error = p.create_client(int(address), 0)   # address = host SteamID64
       return p if last_error == OK else null
   ```
   Steam relay (SDR) gives NAT traversal and hides IPs for free.
2. Register it: `NetTransport.register("steam", "res://systems/net/transport/SteamTransport.gd")`
   (or add it to `_registry`), then `NetSession.transport = NetTransport.create("steam")`
   before hosting/joining (servers: `--transport steam`).
3. Web builds: `WebSocketMultiplayerPeer` (`create_server(port)` / `create_client("wss://host:port")`)
   or `WebRTCMultiplayerPeer` (needs a signalling service) as another subclass.
   ENet is unavailable on web.

## Path to production hosting

* **Build:** export a Linux *Dedicated Server* preset (strips textures/audio,
  keeps scripts + resources), run with `-- --server --port $PORT`. Containerise
  (small base image + the export; expose UDP `$PORT`; log to stdout; the
  heartbeat line doubles as a liveness probe; `--max-matches 1` makes each
  container one match — simplest scaling and isolation).
* **Matchmaking / lobby service:** a small HTTP service (or platform lobbies:
  Steam, EOS, …) pairs players, asks an orchestrator (Agones, Nomad, ECS/Fargate,
  Edgegap, Hathora …) for a server, and hands both clients `address:port` plus a
  **join ticket**. Next step for the server: verify the ticket in `_rpc_announce`
  (HMAC signed by the matchmaker) so only the matched players can take the seats.
* **NAT / relay:** a dedicated server with a public IP needs no NAT traversal.
  Player-hosted over the internet needs port forwarding, UPnP (`UPNP` class), or
  a relay (Steam SDR via SteamTransport, WebRTC TURN).
* **Security:** ENet is plaintext — use DTLS (`ENetConnection.dtls_server_setup`
  / `dtls_client_setup`) or the platform relay's encryption. Rate-limit intents per
  peer; cap name length (done) and payload shape (done: `NetProtocol.is_well_formed`).
* **Reconnect / spectators** are not implemented: the per-seq action log plus the
  commit-reveal transcript is a full, verifiable replay, which is the natural base
  for both.

## Testing

**In process** (real ENet on 127.0.0.1, every peer a subtree with its own
`SceneMultiplayer`):

| Test | Covers |
|---|---|
| `tests/unit/test_net_commit_reveal.gd` | chains, tamper/replay/out-of-order detection, re-commit, 3 contributors, seed unknowable until all reveal |
| `tests/integration/test_net_lobby.gd` | seating, ready, single-shot start, rejects, leave |
| `tests/integration/test_net_match.gd` | validation, identical apply, turns (Traditional/Speed First), desync, disconnects, multi-floor |
| `tests/integration/test_net_rng.gd` | host-as-actor cannot derive before the client reveals; tampered client / host shares end the match; withheld reveal times out; re-commit over 12 actions; host cannot puppet or cheat illegal actions past a client |
| `tests/integration/test_net_dedicated.gd` | seatless server + 2 clients: seating, 3rd client rejected, locked vs leader config, auto-start, 3 contributors, identical play, actor cannot derive until the other client reveals, server-only RNG, disconnect → lobby → second match, closing a finished match |
| `tests/integration/test_net_lobby_ui.gd` | the real lobby screen joined to a dedicated server |

```
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit,res://tests/integration -gprefix=test_net -gexit
```

**Multi-process** (1 dedicated server + 2 scripted headless clients, each a
separate Godot process running the full GameWorld):

```
GODOT=/path/to/godot dev_scripts/net_multiprocess_check.sh \
    [res://game/maps/resources/default_skirmish.tres] [traditional|speed_first] [actions] [all|server]
```

It passes when the server and both bots print the same `FINAL seq=… digest=…`
with no desync / verification failure. `HOSTED=1` runs the player-hosted
variant (a host bot = listen server + seat 0, and a guest bot). A bot alone:
`godot --headless --path . -- --net-bot --connect 127.0.0.1 --port 8910 --name BotA`
(add `--host [--map … --turn-system … --end-after-actions N]` to make it the player-host).
Large maps are slow with the naive bot (it pre-validates every candidate intent).

**Two interactive instances:** Debug → *Customize Run Instances…* → 2, Run;
Host in one, Join `127.0.0.1` in the other (or both Join a local dedicated server).

## Known limitations

* 1v1 humans only; no AI seats in network play. No reconnect.
* Desync is detected (digest mismatch → match ends), not repaired.
* ENet is unencrypted (see *Path to production hosting*).
* One match per server process (see *Dedicated server*).
