# systems/net — Network multiplayer

Network versus is built on ONE stack: Godot's scene-tree `multiplayer` API with
an ENet peer, host-authoritative, 1v1. The old layered stack
(`systems/networking/*`, `systems/multiplayer/*`, `game_core/GameManager` +
network handlers, `MultiplayerLauncher`, `AutoClientDetector`, the
`CollaborativeLobby`) has been deleted.

## Pieces

| File | Role |
|---|---|
| `NetSession.gd` (class `NetSessionNode`, autoload `NetSession`) | Transport, lobby, peer→slot seating, intent queue, action ordering (seq), checkpoints, disconnects. Knows nothing about units. |
| `NetProtocol.gd` | Wire format: action types (`MOVE`, `USE_MOVE`, `WAIT`, `END_TURN`), builders, shape validation, and THE cell (de)serialiser (`cell_to_wire` / `cell_from_wire`: `[col, row, floor]` via `Cells.to_array` / `from_variant`, see docs/MULTI_FLOOR.md). |
| `NetGameRules.gd` | Game rules for a match: host-side `validate_intent` and the ONE deterministic `apply_action` every peer runs; `state_digest` for desync detection. Works on any board / turn system handed to it (live game or test fixtures). |
| `NetUnitIds.gd` | Stable unit ids (`"<slot>:<n>"` at match start, `"<slot>:s<k>"` for mid-match spawns) stored as `net_id` meta; `find(board, id)`. |
| `systems/game_core/GameModeManager.gd` (autoload) | Live-game glue: applies the host's match config to `GameSettings`, loads the battle, builds `NetGameRules` over `CombatServices.board()` + the active turn system, exposes `request_move / request_use_move / request_wait / request_end_turn` to the UI, handles disconnect/desync → main menu, and `end_network_session()` which restores local play. |
| `menus/NetworkMultiplayerSetup.gd` | Host / join by IP:port and the lobby (players, ready, host picks map + turn system, Start). |

## Flow

```
Lobby   host_game(name, port)          join_game(addr, name, port)
        host seats peers (max 2; extras get join_rejected("lobby_full"),
        late joiners "match_in_progress"); set_ready; host set_match_config
        start_match(): only when full + everyone ready; single-shot.
        -> match config {map_path, turn_system, seed, slots, auto_end_turn}
           broadcast to all; GameModeManager loads GameWorld on every peer.

Match   UI --request_*--> submit_intent --rpc--> host intent queue
        host: NetGameRules.validate_intent(action, sender's seat)
              (turn owner? unit owned? MovementResolver-reachable?
               move.can_aim_at/can_target + eligible target? cooldown?)
              rejected -> intent_rejected to the sender only
              accepted -> stamp {actor, seq}, broadcast, apply locally
        every peer: apply_action (at most ONE per frame, so deferred turn
              logic -- auto end-of-turn, death cleanup -- settles identically
              before the next action)
        host, next frame: checkpoint {seq, turn slot, digest} -> clients
              compare their own digest (desync_detected) and learn whose turn.
```

* **Actor is the sender's seat**, never a field of the payload.
* **Apply uses the local-play primitives**: `board.move_unit` +
  `GameEvents.unit_moved` + `mark_moved`; `Unit.perform_move` (MoveExecutor) +
  `MovesetController.on_used` + `mark_action_completed`; `turn_system.mark_unit_acted`
  (wait); `end_turn_manually`. Hotseat / single-player keep their direct paths
  untouched — the UI only branches when `GameModeManager.is_multiplayer_active()`.
* **Determinism**: each accepted action gets an RNG seeded from
  `hash([match_seed, seq])`, passed into `perform_move` and installed as
  `CombatServices.match_rng`, which `MoveContext` falls back to, so abilities,
  status ticks and tile effects roll identically too. Forced-control turns use
  the deterministic NORMAL planner for the match.
* **Turns** are derived: both peers run the same turn system
  (Traditional or Speed First) over the same applied actions; the host's
  checkpoint carries the authoritative active slot and a state digest.
* **Network moves commit immediately** (no Fire-Emblem tentative preview): the
  local board is never mutated outside an accepted action.
* **Disconnects**: a seat dropping mid-match → `match_aborted`; the survivor
  returns to the main menu with a message. After the battle is decided the
  end screen stays up (no Rematch in network games). Reaching the main menu
  always calls `GameModeManager.end_network_session()` (closes the peer, resets
  `GameSettings.game_mode`, local seat back to 0).

## Testing multiplayer locally (two instances, one machine)

**From the editor:** Debug → *Customize Run Instances…* → enable multiple
instances, set 2, then Run. In instance A: Versus → Network → *Host Game*
(default port 8910). In instance B: Versus → Network → address `127.0.0.1`,
same port → *Join Game*. Both tick *Ready*; the host picks map / turn system and
presses *START MATCH*.

**From the command line** (project root):

```
godot --path . &        # instance A: host
godot --path . &        # instance B: join 127.0.0.1:8910
```

Across machines on a LAN, the host shares its LAN IP and the joiner types it
instead of `127.0.0.1` (UDP port must be reachable).

**Automated:** `tests/integration/test_net_lobby.gd` and
`tests/integration/test_net_match.gd` run a host and client (and a rejected
third peer) **in one headless process**: each peer is a subtree with its own
`SceneMultiplayer` (`get_tree().set_multiplayer(api, subtree_path)`) and a
`NetSessionNode` child named `NetSession`, so RPC paths match and real ENet
traffic flows over 127.0.0.1. The match tests give each peer its own board of
real character units, its own turn system and its own `NetGameRules`.

```
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_net_match.gd -gexit
```

## Known limitations

* 1v1 humans only: no AI seats in network play (no bot driver is created);
  units outside the two players' containers (neutral camps) stay inert.
* No reconnect: a dropped peer ends the match.
* Desync is detected (digest mismatch → match ends with a message), not repaired.
* ENet is unencrypted and the host is trusted (listen server).
