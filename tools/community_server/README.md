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
index, `payloads/<id>.json` is each map/challenge body. Requires Python 3.7+; no `pip
install` needed (standard library only).

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

Implements the `/v1/` contract: `GET /v1/items`, `GET /v1/items/{id}`,
`POST /v1/items`, `POST /v1/items/{id}/vote`, `GET /v1/daily`. Votes are idempotent per
`X-Community-Device` header. See `docs/COMMUNITY_API.md` for shapes.

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
