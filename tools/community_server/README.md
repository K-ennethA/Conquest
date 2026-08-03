# Community reference server

A single-file, dependency-free reference implementation of the Conquest community
service contract (see `docs/COMMUNITY_API.md`). It exists for **local development and
testing**, and as the seed for a real deployment. It is **not shipped with the game**.

## Run

```sh
python server.py --port 8787
```

Options: `--host` (default `127.0.0.1`), `--port` (default `8787`), `--data-dir`
(default `./data`). Storage is flat JSON files under the data dir — `items.json` is the
index, `payloads/<id>.json` is each map/challenge body, `attempts/<id>.json` is a base's
attempt ledger (newest first, newest 200 kept) and `replays/<attempt_id>.json` is one
attached replay blob (newest 50 kept per base). Requires Python 3.7+; no `pip install`
needed (standard library only).

## Point the game at it

Create `user://community.cfg` in the game's user data directory:

```ini
[service]
base_url = "http://127.0.0.1:8787"
```

With that file present, `CommunityClient` selects the `HttpProvider` and talks to this
server. Delete the file (or leave it empty) to fall back to the offline `LocalProvider`
sandbox. That one file is the entire switch — no code change.

## Endpoints

Implements the whole `/v1/` contract. See `docs/COMMUNITY_API.md` for the shapes.

| Method | Path | Notes |
| --- | --- | --- |
| `GET` | `/v1/items?sort=&type=&page=&q=` | `sort` = `recommended` (default) \| `top` \| `new` \| `daily`. `q` is a case-insensitive title/author substring, trimmed + capped at 64 chars, applied **before** sort and pagination. Retired items are never listed. |
| `GET` | `/v1/items/{id}` | Full payload. Works for **retired** items — a share code always plays. |
| `POST` | `/v1/items` | Upload. `owner` is stamped from the device header; a 4th challenge lands `active: false` rather than being refused. `409` on a duplicate id. |
| `POST` | `/v1/items/{id}/vote` | `{dir: 1\|-1\|0}`, idempotent per `X-Community-Device`. |
| `GET` | `/v1/daily` | `{id}` of today's pick (active items only). |
| `POST` | `/v1/items/{id}/attempts` | `{cleared, score, turns}` (+ optional `replay_b64`), re-sanitised server-side. **Not** idempotent — every play counts. Returns `attempt_id` + `has_replay`. `404 {"error":"not_found"}`. |
| `GET` | `/v1/items/{id}/attempts?page=N` | **Owner only** ledger page, newest first: `{entries, has_more}`. `403 not_owner`, `404 not_found`. |
| `GET` | `/v1/attempts/{attempt_id}/replay` | **Owner of the base only**: `{replay_b64}`. `404` when the attempt carried no blob or it aged out. |
| `GET` | `/v1/me/bases` | The calling device's own challenges, active *and* retired, newest first. |
| `POST` | `/v1/items/{id}/active` | `{active: bool}`. `403 not_owner`, `409 base_limit` past 3 active; retiring always succeeds. |

The three newest endpoints answer with **machine-readable** error codes (`not_found`,
`not_owner`, `base_limit`) rather than prose, because clients switch on them.
`_recommended_score` mirrors `LocalProvider._recommended_score` term for term, so the
offline sandbox and this server rank a catalogue identically.

## Validation caveat (important)

This scaffold validates only the **structural** shape of an uploaded payload (required
keys, coarse type). The real **catalog-strict** validation — known tile/character ids,
map size bounds, defender presence, checksum recomputation — lives in the Godot code
(`MapResource.validate_map(strict)` + `ChallengeCodec.validate`) and depends on the game
catalog, so it cannot be fully reproduced in this standalone script.

**A production deployment MUST run the full catalog-strict rules server-side and
re-compute the checksum — never trust the client.** Treat this file as the wire-contract
reference and the storage/flow blueprint, not as a security boundary.

## Production path

The intended production service is a free-tier serverless worker/function (e.g. a
Cloudflare Worker or similar) that ports these same endpoints and storage shape, adds
real accounts / rate limiting / anti-abuse, and runs the full validation above.
