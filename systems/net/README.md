# systems/net — Network multiplayer

Network versus is built on ONE stack: Godot's scene-tree `multiplayer` API,
host-authoritative, 1v1, over a pluggable transport (ENet by default). The
host is either a **player** (listen server, seat 0) or a **dedicated headless
server** with no seat. Combat randomness is **commit-reveal**: no peer — the
host included — can know or bias a roll before the action that consumes it is
irrevocably accepted. Every peer re-validates and applies every accepted action
through ONE deterministic apply path and compares a state digest after each one.

This is the merge of two branches' work: the anti-cheat core (commit-reveal RNG,
validate-on-every-peer, digest checkpoints, dedicated server, transports) and the
game-facing features built on top of the earlier core (join build gate, lobby
channel + collaborative lobby, squad / item / skin replication, forfeit, rejection
toasts, apply-side ultimates and cooldown booking, replays, dev auto-join).

## Pieces

| File | Role |
|---|---|
| `NetSession.gd` (class `NetSessionNode`, autoload `NetSession`) | Join handshake (build gate), lobby, peer→slot seating, the lobby message channel, intent queue, action ordering (seq), the commit-reveal rounds, checkpoints, disconnects / forfeit. Player-hosted (`host_game`) and dedicated (`host_dedicated`) modes share every code path. Also holds the per-battle **seam** (`install_command_seam`: the `CommandApplier` replays drive) and the solo RNG stream. Knows nothing about units. |
| `NetCommitReveal.gd` | Hash-chain commitments, share verification, epoch re-commit, per-action seed derivation. Pure (no networking), unit-tested. |
| `transport/NetTransport.gd`, `transport/ENetTransport.gd` | The only place a `MultiplayerPeer` is created. See *Adding a transport*. |
| `NetProtocol.gd` | Wire format: actions (`MOVE`, `USE_MOVE`, `WAIT`, `END_TURN`; the command-log names `MOVE_UNIT` / `CAST_MOVE` / `WAIT_UNIT` are aliases), builders, shape validation, THE cell (de)serialiser (`[col, row, floor]`, see docs/MULTI_FLOOR.md), `KEY_RNG` (locally stamped seed, never trusted from the wire), the join hello + `validate_hello` + `describe_rejection`, the `INTENT_*` rejection vocabulary + `describe_intent_rejection`, `PROTOCOL_VERSION`. |
| `NetGameRules.gd` | `validate_intent` (host; re-run by clients) and THE deterministic `apply_action` every peer runs — incl. replay recording, the ultimate cut-in announcement, cooldown / charge booking, canto hand-off; `state_digest` for desync detection. |
| `CommandApplier.gd` | `NetGameRules` bound to the live battle under the name the battle / replay code uses (`apply_command(cmd, board, ctx)`, `hash_match_state`). A subclass, never a second apply path. |
| `NetUnitIds.gd` | Stable unit ids (`"<slot>:<n>"`, mid-match arrivals `"<slot>:s<k>"`). |
| `MatchLoadouts.gd`, `MatchPeerInfo.gd` | Process-wide parking for the other participants' `match_loadout` (squad / items / skins, whitelisted) and `profile_info` (name / rank / points) cards, keyed by host-stamped slot. |
| `MatchRng.gd` | The SOLO / replay per-command stream (one local seed). Not used by network play. |
| `DedicatedServer.gd` | Headless server driver: args, lobby, match lifecycle, sequential matches, logs. |
| `systems/game_core/GameModeManager.gd` (autoload) | Live-game glue (match config → `GameSettings` incl. custom-map gate + squads, battle load, rules attach, `request_*` intents, opponent-left → victory, desync / cheat → menu message) and command-line boot of `--server` / `--net-bot`. |
| `menus/NetworkMultiplayerSetup.gd` | Host / join by address:port (a friend's game or a dedicated server): validation, remembered details, connect countdown, rejection text, LAN addresses; embeds the lobby. |
| `menus/CollaborativeLobby.gd` | The lobby: roster + ready, map votes / coin flip (player-hosted) or the leader's pick (dedicated), host match settings, profile + loadout exchange, the start. |
| `systems/multiplayer_launcher.gd` (autoload `MultiplayerLauncher`), `systems/AutoClientDetector.gd` | Dev two-instance auto-join (`-- --multiplayer-auto-join`) and the dev-gated "Host + Auto Client" spawner. |
| `dev_scripts/net_bot_client.gd`, `dev_scripts/net_multiprocess_check.sh` | Scripted headless client + the 3-process check (see *Testing*). |

## Flow

```
Join     client hello {name, PROTOCOL_VERSION, game version}  ->  host build gate
         (validate_hello): protocol mismatch -> join_rejected("version_mismatch", info);
         lobby full / match running -> "lobby_full" / "match_in_progress"; else seated.

Lobby    host_game(name, port)  |  host_dedicated(port, cfg, rng_mode)  |  join_game(addr, name, port)
         host seats peers (max 2); set_ready; lobby channel (votes, profile + loadout
         cards); config by the player-host, or on a dedicated server by --map /
         --turn-system (locked) or the slot-0 client (lobby leader).
         start_match(final_config): full + all ready, single-shot (a dedicated server
         auto-starts). The player-host's lobby passes its last word here: the voted
         map (+ its content if custom), host_squad, versus_rounds.

Commit   host: fresh secret chain, broadcast (contributors, chain length, host anchor)
         each contributing client: fresh chain -> its anchor -> host
         host: all anchors in -> match_started {config..., slots, anchors,
               seed = setup seed derived from the anchors}
         clients check their own + the host's anchor are the ones committed.
         GameModeManager (every peer): config -> GameSettings, load GameWorld.

Match    UI --request_*--> submit_intent --rpc--> host intent queue
         host (one intent at a time, only when no RNG round is in flight):
             validate_intent(action, sender's seat) -> rejected: intent_rejected(reason)
             accepted -> stamp {actor, seq}; broadcast ACCEPTED(action, host share)
         clients: verify the host share against the host chain; check an action
             in their own seat is the intent they sent; THEN reveal their share
         host: verify each share, relay ROUND(seq, shares) to everyone
         every peer: verify, seed = H(shares || seq), apply_action (<= 1 per frame;
             clients first re-validate it on their own state)
         host, next frame: checkpoint {seq, turn slot, digest} -> clients compare.
```

* **Actor is the sender's seat**, never a field of the payload.
* **Apply uses the local-play primitives** (`board.move_unit` + `GameEvents.unit_moved` +
  `mark_moved`; `Unit.perform_move` + `MovesetController.on_used` + `mark_action_completed`;
  `mark_unit_acted`; `end_turn_manually`). Hotseat / single-player keep their direct paths.
* **Turns** are derived: every peer runs the same turn system over the same
  applied actions; the host's checkpoint carries the authoritative active slot.
  (The earlier turn-ownership *bridge* is gone — the validator reads the rules' turn system.)
* **Leaving a live match is a loss.** A seat dropping mid-match raises `opponent_left`
  (then `match_aborted("opponent_disconnected" | "host_disconnected")`); a deliberate
  `forfeit_match()` is announced first on the lobby channel (`MSG_MATCH_FORFEIT` →
  `opponent_forfeited(slot)`, slot stamped by the host). The battle HUD
  (`UILayoutManager`) eliminates the absent side, so the one who stayed gets the normal
  victory screen; GameModeManager keeps the battle up and just drops the link. Before the
  battle is up (or on a dedicated server) an abort returns to the menu with a message. A
  dedicated server returns to an empty lobby for the next pair.

## Join handshake (the build gate)

A joining client's **first** message is a hello — display name plus
`NetProtocol.PROTOCOL_VERSION` and `application/config/version`. The host runs the pure
`NetProtocol.validate_hello()` **before** the peer gets a roster slot:

- different `PROTOCOL_VERSION` → `join_rejected("version_mismatch", info)` on the client
  (`peer_join_refused` on the host), then the peer is dropped after a short flush;
  `NetProtocol.describe_rejection(reason, info)` is the line a menu shows;
  `last_join_rejection()` survives the disconnect.
- same protocol, different game version → admitted, `build_differs` logged
  (an editor run joining an exported build is a legitimate test setup).

Bump `PROTOCOL_VERSION` whenever the envelope or an action's data shape changes (2 = this
merged core). Replays stamp it too and refuse other versions. Two-machine procedure:
`docs/NETWORK_TESTING.md`.

## Lobby channel

Pre-match traffic (map votes, ready flags, profile / loadout cards, the informational
game-start line, forfeits) is **not** part of the action vocabulary — it is never
validated, sequenced or RNG-stamped, and must never mutate battle state:

```gdscript
NetSession.lobby_message.connect(_on_lobby_message)   # (type, data, from_slot)
NetSession.send_lobby_message("map_vote", { "map_path": path })
```

The host relays; **the sender never receives its own message back**, so a lobby UI can
broadcast unconditionally. Only seated peers may send. Treat `data` as untrusted peer
input. (A player-host is a participant and receives relayed messages; a dedicated server
also sees them but has no lobby UI.)

## Match settings: whose squad is whose

A `player_id` on a map is a **roster slot**, and the same slot must field the same characters
on every machine. `MapLoader.resolve_player_squad(player_id, local_squad, replicated_squad,
local_slot, networked)` is the one rule that says which pick is authoritative:

| | `player_id == local_slot` | any other `player_id` |
|---|---|---|
| **not networked** | the local pick (player 0 only) | the map's authored roster |
| **networked** | the local pick | that slot's **replicated** pick |

Slot 0's pick rides the match config (`host_squad`, set from the player-host's lobby); every
other slot's pick rides its `match_loadout` card. Squads are untrusted input and normalised at
the boundary (`MapLoader.normalise_squad_ids`, `MatchLoadouts.normalise_squad` with a
`CharacterLibrary` whitelist). An empty squad means "field the map's authored roster" on every
peer. Squad-picked spawns are exempt from the per-peer `min_difficulty` gate.

**Without a loadout exchange every peer fields map rosters.** GameModeManager keeps the local
pick only when `MatchLoadouts.is_active()` and the host is not a dedicated server; otherwise it
clears the pick and `host_squad` on every peer (a seatless server runs no lobby UI and could
not know the clients' picks). Pinned by `tests/integration/test_net_host_squad.gd`,
`test_net_client_squad.gd` and `tests/unit/test_game_mode_manager.gd`.

**Custom / community maps** travel as content: the player-host puts `map_payload` in the
final config; every other peer strict-validates it and boots from its own installed copy
(`GameModeManager.resolve_boot_map` → `MapCatalog.install_session_payload`), or refuses the
match. Never a same-named local file.

**Offline-only maps.** Network versus seats two humans and runs **no AI** on any peer, so a map
that needs AI turns is never played online: one that fields units on player slot 2+ (an
AI-controlled neutral faction — Riftwood's jungle camps, King's Crossing's guardians; the mode
layer registers it as a third, AI player with its own turn) or that authors Siege creep
`lanes` (creep waves are AI-driven — only `BotTurnDriver` moves them). The one rule is
`MapCatalog.network_refusal(path)` (codes `NET_REFUSAL_*`, wording
`describe_network_refusal`; `network_eligible` is `network_refusal == ""`), applied at every
door: the lobby's map rows (disabled, tagged "Offline only", the reason as the tooltip), a
dedicated server's `--map` (refused at boot) and leader-config sanitiser (the pick is dropped,
the previous map kept), and `GameModeManager.apply_match_config` on every peer (the match is
refused with `offline_only_map`). Backstop: if the rules ever hand the turn to a slot no seat
occupies, the host ends the match with `NetSessionNode.ABORT_UNDRIVEN_TURN` instead of waiting
forever. Offline pickers still offer these maps exactly as before. Pinned by `tests/unit/test_net_offline_only_maps.gd`,
`tests/integration/test_net_undriven_turn.gd` and `test_net_dedicated.gd`.

## Squad, loadouts and skins: `match_loadout`

Equipped items are real buffs and skins change what a unit looks like, and both live in
process-local storage, so **both** machines need **both** sides' data before a unit spawns:

```gdscript
NetSession.send_lobby_message("match_loadout", {
    "squad":    ["<character_id>"],                   # this peer's pick, in order, MAX_SQUAD max
    "equipped": { "<character_id>": "<item_id>" },   # UNIT-scope items, per character
    "team":     ["<item_id>"],                        # TEAM slots, ItemInventory.TEAM_SLOTS max
    "skins":    { "<character_id>": "<skin_id>" },    # cosmetic skin per character
})
```

`CollaborativeLobby` sends one card per peer (host: on admitting the opponent; client:
alongside its `lobby_hello`); cards are parked in `MatchLoadouts` by host-stamped slot and
survive the scene change. `MatchLoadouts.set_local_slot()` switches replication on — solo /
hotseat / arena leave it unset. `ItemSystem` equips every human slot through one
`apply_loadout_items()`; `Unit.apply_equipped_skin` asks `MatchLoadouts.skin_for`.
State is cleared when a new lobby forms and when a non-networked battle builds its board
(`MapLoader._clear_stale_replication`). `MatchLoadouts.normalise()` whitelists every id
(library + scope + character), caps sizes; a hostile peer can only field fewer buffs than it
claimed. Pinned by `tests/unit/test_match_loadouts.gd`, `test_lobby_loadout_exchange.gd`.

## What the player sees at the seam

- **Refused commands are surfaced.** The origin peer gets `intent_rejected(action, reason)`
  with a `NetProtocol.INTENT_*` reason (the rules' specific one: `not_your_turn`,
  `illegal_destination`, `move_unavailable`, …); the battle HUD's `NetToast` renders
  `NetProtocol.describe_intent_rejection(reason, action)` — "Move rejected — that unit cannot
  move there". GameModeManager draws a plain fallback line only when no NetToast is mounted.
  Pinned by `tests/unit/test_net_intent_rejection.gd`, `tests/integration/test_net_rejection_toast.gd`.
- **Ultimates flash on every peer.** `NetGameRules` emits `GameEvents.ultimate_casting` when
  an applied `USE_MOVE` is an ultimate, so a remote opponent's ultimate plays the cut-in here
  too; the battle UI's networked submit branch does not play it, so the caster flashes once
  and never for a refused cast. Pinned by `tests/unit/test_command_applier_ultimate.gd`.
- **Cooldowns and charges are booked apply-side** (`MovesetController.on_used` after
  `perform_move`, preserving a wait the resolution set for itself — Voidstep's teleport).
  The digest includes cooldowns and statuses, so an unbooked cooldown is a detected desync.
  Pinned by `tests/integration/test_net_cast_cooldown.gd`.

## Replays and solo play ride the same apply path

Every battle (solo too) installs a `CommandApplier` on NetSession
(`install_command_seam`) and names its units with `NetUnitIds`. Solo / hotseat seed a
per-command stream with `begin_solo_match_rng()` (`MatchRng`). `ReplayRecorder` records
networked actions from inside `apply_action` (exactly once per peer) and solo commands from
the UI / AI commit sites, in this same vocabulary; `ReplayDriver` plays them back through
`NetSession.command_applier.apply_command`. A recorded network action keeps its verified
seed (`KEY_RNG`), so playback rolls exactly what the match rolled; an unstamped (solo) command
draws from the replay header's `match_seed` stream.

## Unpredictable, unriggable combat RNG (commit-reveal)

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
forfeit — a loss, never a re-roll). The setup seed (only rolls before the first
action) is derived from the anchors, so the last committer could grind it --
this only affects rolls made while the battle is set up (e.g. a turn-1 start
tick of a map-authored tile effect), never a player-chosen action.

(The earlier single-match-seed commit/entropy/reveal handshake in `MatchRng` is superseded
by this; `MatchRng` remains only as the solo / replay stream.)

## Trust model

| | Player-hosted (listen server) | Dedicated server |
|---|---|---|
| Who validates | host (a player) — clients re-validate every accepted action on their own state and refuse illegal ones | server — clients re-validate too |
| Actions in your seat | only ones you submitted (host cannot puppet your units: forged → match ends) | same; the server derives the actor from the sending seat |
| Roll prediction | impossible for either player (both contribute) | impossible for clients; the server could only learn rolls post-accept |
| Roll biasing | impossible (committed chains) | impossible for clients; `rng server` mode trusts the server |
| Host-private info | host sees everything a client sends | server sees everything |
| State divergence | per-action digest checkpoint → `desync_detected` → match ends | same |
| Lobby payloads (squads, items, skins, custom maps) | untrusted: whitelisted / strict-validated on receipt; no ownership proof yet | not used (map rosters) |
| Remaining trust | the host process can still refuse / delay your intents, drop you, or run modified rules on ITS copy (you'd see a desync, not a silent change); ENet is unencrypted | operator runs the server; same transport caveat |

**Fog of war** (per-team vision) is presentation-only in network play: every peer holds the
full state because it must re-validate and apply every action, so a modified client — and a
player-host by construction — can see through fog. The fog overlay reads
`NetSession.local_slot()` for its perspective. Only a dedicated server that withheld state
could keep secrets (not implemented). Validation may also reveal information (e.g. a move
refused because an unseen unit blocks the path).

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
conditions). Clients join with the normal **Join** (address:port): the
lobby shows the two players, no host seat. **Lobby leader:** with `--map` the
config is locked; without it the slot-0 client picks map / turn system (the
server sanitises it; builtin, network-eligible maps only -- see *Offline-only maps*). The match starts when both are ready. When it is decided
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
commit-reveal, the lobby channel) is transport-agnostic.

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
  **join ticket**. Next step for the server: verify the ticket in the hello
  (`_host_admit_peer`, HMAC signed by the matchmaker) so only the matched players can take the seats.
* **NAT / relay:** a dedicated server with a public IP needs no NAT traversal.
  Player-hosted over the internet needs port forwarding, UPnP (`UPNP` class), or
  a relay (Steam SDR via SteamTransport, WebRTC TURN).
* **Security:** ENet is plaintext — use DTLS (`ENetConnection.dtls_server_setup`
  / `dtls_client_setup`) or the platform relay's encryption. Rate-limit intents per
  peer; cap name length (done) and payload shape (done: `NetProtocol.is_well_formed`).
* **Reconnect / spectators** are not implemented: the per-seq action log plus the
  commit-reveal transcript is a full, verifiable replay (the replay system already
  records it), which is the natural base for both.

## Testing

**In process** (real ENet on 127.0.0.1, every peer a subtree with its own
`SceneMultiplayer`), plus pure / mock-board suites:

| Test | Covers |
|---|---|
| `tests/unit/test_net_protocol.gd`, `test_command_protocol.gd` | wire shapes, builders, the command-log aliases, cells, resolution stamp |
| `tests/unit/test_net_handshake.gd` | the build gate (`validate_hello`), pure |
| `tests/unit/test_net_intent_rejection.gd` | the player-facing rejection wording, pure |
| `tests/unit/test_net_commit_reveal.gd` | chains, tamper/replay/out-of-order detection, re-commit, 3 contributors, seed unknowable until all reveal |
| `tests/unit/test_command_determinism.gd`, `test_command_applier_ultimate.gd` | the apply path on mock boards: lockstep, flags, digest, spawn ids, ultimate announcement |
| `tests/unit/test_match_rng.gd` | the solo / replay stream |
| `tests/unit/test_game_mode_manager.gd` | local defaults, session teardown, match config → GameSettings (squads, custom-map gate) |
| `tests/unit/test_match_loadouts.gd`, `test_lobby_*.gd`, `test_collaborative_lobby.gd` | loadout normalisation, the lobby's transport adapter, votes, loadout / profile exchange, custom-map transmission |
| `tests/integration/test_net_lobby.gd` | seating, ready, single-shot start, rejects (full / in progress / **version mismatch**), leave, the **lobby channel**, `start_match(final_config)`, **forfeit over a socket** |
| `tests/integration/test_net_match.gd` | validation, identical apply, turns (Traditional/Speed First), desync, disconnects, multi-floor |
| `tests/integration/test_net_rng.gd` | host-as-actor cannot derive before the client reveals; tampered client / host shares end the match; withheld reveal times out; re-commit over 12 actions; host cannot puppet or cheat illegal actions past a client |
| `tests/integration/test_net_dedicated.gd` | seatless server + 2 clients: seating, 3rd client rejected, locked vs leader config, auto-start, 3 contributors, identical play, actor cannot derive until the other client reveals, server-only RNG, disconnect → lobby → second match, closing a finished match |
| `tests/integration/test_net_lobby_ui.gd` | the real setup screen + lobby joined to a dedicated server |
| `tests/integration/test_mp_loopback.gd` | two-peer lockstep on mock boards, turn validation, the battle seam, host-side seating + relay |
| `tests/integration/test_net_forfeit.gd` | forfeit / opponent-left semantics (host-stamped slot, no echo, loss on disconnect) |
| `tests/integration/test_net_cast_cooldown.gd` | apply-side cooldown / charge booking, the maxi rule, lockstep, replay round trip |
| `tests/integration/test_net_host_squad.gd`, `test_net_client_squad.gd` | squad replication per slot through MapLoader |
| `tests/integration/test_net_rejection_toast.gd` | refused command → NetToast |

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
Or start the second instance with `godot --path . -- --multiplayer-auto-join
[--multiplayer-port 8910]` (MultiplayerLauncher) — it opens the setup screen and presses
Join for you, on the same code path a human uses. The dev-gated "Host + Auto Client"
button (`NetworkMultiplayerSetup.ENABLE_HOST_AUTO_CLIENT`) spawns exactly that.
**Two machines:** `docs/NETWORK_TESTING.md`.

## Known limitations

* 1v1 humans only; no AI seats in network play. No reconnect.
* Desync is detected (digest mismatch → match ends), not repaired.
* ENet is unencrypted (see *Path to production hosting*).
* One match per server process (see *Dedicated server*).
* Squads / items / skins replicate only in player-hosted lobbies; dedicated matches field map rosters.
* Fog of war cannot hide information from a modified client (see *Trust model*).
