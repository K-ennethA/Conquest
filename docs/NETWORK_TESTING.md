# Two-machine network testing

How to build Conquest, get it onto a second machine, and play a networked match — plus what
is honestly expected to work today and what is not. Follow it top to bottom the first time.

---

## 1. Build the shared exe (machine A, once per test round)

The project ships **`export_presets.cfg`** at the repo root with two presets:

| Preset | Platform | Runnable | Output |
|---|---|---|---|
| `Windows Desktop` | Windows Desktop | yes | `build/Conquest.exe` (PCK embedded — one file) |
| `Android (stub)` | Android | **no** | `build/Conquest.apk` (placeholder; mobile renderer work pending) |

The Windows preset embeds the PCK, so the export is a **single self-contained .exe** — that is
the only file you copy to the second machine.

**From the editor:** `Project → Export…` → select *Windows Desktop* → `Export Project…` →
save as `build/Conquest.exe` → untick *Export With Debug* for a release build.

**From the command line** (same result, no editor):

```bash
godot --headless --export-release "Windows Desktop" build/Conquest.exe
```

Requirements and gotchas:

- **Export templates must be installed** for your exact Godot version (`Editor → Manage Export
  Templates…`). Without them the export fails with "No export template found".
- `build/` is git-ignored; `export_presets.cfg` is **committed on purpose** so both machines
  build the identical exe. Never put a keystore password or encryption key in it.
- `dev_scripts/`, `tests/`, `docs/`, `tools/` and `addons/gut/` are excluded from the export —
  the shipped exe is the game, not the harness.
- The exe writes its save data and logs to `%APPDATA%\Godot\app_userdata\Conquest\`.

## 2. Get it onto machine B

Copy `build/Conquest.exe` to machine B (USB stick, network share, Drive — anything). **Both
machines must run the exe built from the same commit.** Mismatched builds are refused at
connect time (see §5), which is deliberate — a silent desync is far worse than a clean refusal.

Both machines must be on the **same LAN / router / Wi-Fi**. This is plain ENet over the local
network: there is no relay, no NAT punch-through, no matchmaking server. Playing across the
internet needs port forwarding on the host's router (TCP+UDP `8910`) and the host's public IP,
which is out of scope for a feature test.

## 3. Host on machine A

1. `Main Menu → Versus → Network`.
2. Set your name (and the port, default `8910`) and press **Host Game**.
3. **Windows Firewall will pop up the first time.** Tick **Private networks** and click
   *Allow access*. If you miss it, machine B will never connect. To fix it afterwards:
   `Windows Security → Firewall & network protection → Allow an app through firewall` → find
   *Conquest* → tick **Private**.
4. The lobby opens and shows, in a line that stays visible while you wait:
   `Players on your network join:  192.168.x.x:8910`
   Read that address out to machine B. If it says *"No private network address found"*, the
   machine is not on a normal LAN (VPN, mobile hotspot, disconnected adapter) — fix that first.

(Or run a **dedicated server** on any machine — `godot --headless --path . -- --server --port 8910`
— and have both players Join it; see `systems/net/README.md` → *Dedicated server*.)

## 4. Join from machine B

1. `Main Menu → Versus → Network`.
2. Type the address machine A displayed into **Host address**, keep the port at `8910`, set a
   name. The address, port and name are remembered in `user://net.cfg` — the next run
   pre-fills them.
3. Press **Join Game**. The status line walks through explicit states:
   - `Connecting to 192.168.x.x:8910 ... (7s)` — a visible countdown, never a frozen spinner.
   - the lobby opens once the host has seated you (after the version gate, §5).
   - `Could not reach 192.168.x.x:8910 - check the address, that the host clicked Host, and
     that Windows Firewall allowed Conquest on both machines.` after ~8s.
   - `Version mismatch: host 0.1.0 (protocol 2), you 0.2.0 (protocol 3). Both machines must
     run the same build.` — you are on different builds; rebuild and recopy.
   - `The host's lobby is full.` / `A match is already in progress on that host.`
   Malformed input is caught before the socket is touched, so a typo'd address says so
   immediately instead of burning the timeout.

## 5. The version gate (why a mismatch is refused)

`NetProtocol.PROTOCOL_VERSION` is the wire-format version. A joining client's **first** message
is a hello carrying its protocol version and its game version
(`application/config/version`, or `"dev"` when unset). The server runs
`NetProtocol.validate_hello()` **before** giving the peer a roster slot:

- **Different `PROTOCOL_VERSION` → refused** with reason `version_mismatch`, and the client is
  told both sides' versions before being disconnected.
- **Same protocol, different game version → admitted**, but logged on the host
  (`[NET] Peer 2 joined on game version 'dev' while this host runs '0.1.0'`). Running the
  editor against an exported build is a legitimate test setup, so it is not fatal — but if you
  are chasing a desync, that log line is the first thing to check.

Bump `PROTOCOL_VERSION` whenever the action envelope or any action's data shape changes (it is
also stamped into replay files, which refuse to play under another version).

## 6. What SHOULD happen, end to end

| Stage | Expected on machine A (host) | Expected on machine B (client) |
|---|---|---|
| Lobby | Client appears in the player list | Lobby opens, both players listed |
| Squads / items / skins | each side's Character Select pick, equipped items and skins are exchanged (`match_loadout`) | same |
| Map vote | Both vote; matching votes win, differing votes coin-flip; a custom map is shipped as content | same map resolved on both |
| Ready | both mark ready; the host starts (a dedicated server starts on its own) | "Starting…" |
| Battle load | `GameWorld` loads the agreed map | same map, same units, same squads |
| Move a unit | unit slides to the cell | **the same move plays here** |
| Cast a move | damage/heal numbers, status icons, ultimate cut-in | **identical numbers**, the same cut-in |
| Refused action | an amber toast names the action and why ("Move rejected — not your turn") | same, on whoever sent it |
| End turn | turn passes | turn indicator flips in step |
| Forfeit / disconnect | the one who stays wins (standard victory screen) | same |

The seam that makes this work: the acting peer never mutates its own board. It submits an
intent; the **host** validates it (`NetGameRules.validate_intent`) and broadcasts it as
accepted with a sequence number; each RNG contributor then reveals its commit-reveal share for
that action, every peer verifies every share, derives the action's seed, re-validates the action
on its own state, and applies it through the ONE apply path (`NetGameRules.apply_action`).
After every action the host sends a checkpoint digest; a mismatch ends the match with a
"went out of sync" message instead of letting the two screens drift. So both machines roll the
same crit off the same seed — and nobody, the host included, can know or bias that roll before
the action is locked in.

## 7. Known limitations — test around these, don't report them as new

1. **1v1 only**, humans only (no AI seats in network play), no reconnect.
2. **Dedicated-server matches field the maps' authored rosters** — squads / items / skins are
   replicated only in player-hosted lobbies (a seatless server has no lobby UI to receive the
   cards). A dedicated server also only offers builtin maps.
3. **Fog of war is presentation-only in network play.** Every peer holds the full state (it has
   to, to re-validate and apply every action), so a modified client — or a player-host — can see
   through fog. Only a dedicated server could keep secrets.
4. **ENet is unencrypted.** Fine on a LAN; see `systems/net/README.md` for the production path.
5. **`Host + Auto Client`** is a dev-only two-instance harness, hidden and disabled
   (`ENABLE_HOST_AUTO_CLIENT = false`); a second instance can also be started with
   `-- --multiplayer-auto-join`. Neither is a substitute for a real two-machine test.

## 8. Capturing logs for a bug report

Godot writes a rolling log per run on both machines:

```
%APPDATA%\Godot\app_userdata\Conquest\logs\godot.log
```

(Paste that path into Explorer's address bar. Older runs are kept alongside as
`godot_YYYY-MM-DD_HH.MM.SS.log`.) The join prefs live next to it in
`%APPDATA%\Godot\app_userdata\Conquest\net.cfg`.

For a useful report:

1. Reproduce, then **close both games** so the logs are flushed.
2. Grab the newest `godot*.log` from **both** machines — a networked bug is only diagnosable
   with both halves.
3. Note which machine hosted, both game versions (the host prints them when a peer joins on a
   different build), and the wall-clock time of the divergence.
4. Useful greps: `[NET]` (version notices), `NetSession:` (refusals, DESYNC, verification
   failures), `[HOST]` / `[CLIENT]` (the setup screen's flow).

To watch a run live instead, launch from a terminal — the same lines go to stdout:

```bash
Conquest.exe --verbose
```

## 9. Fast checklist

- [ ] Same commit on both machines, exe rebuilt after any code change
- [ ] Both on the same router; host firewall prompt allowed for **Private** networks
- [ ] Host clicked **Host Game** and the lobby shows a `192.168.x.x:8910`-style address
- [ ] Client typed that exact address (not `127.0.0.1` — that only reaches its own machine)
- [ ] The lobby opened on both, both names listed
- [ ] Logs from **both** machines saved before filing anything
