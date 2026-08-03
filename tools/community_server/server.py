#!/usr/bin/env python3
"""Reference community service for Conquest -- local dev + testing.

Implements the contract in docs/COMMUNITY_API.md using ONLY the Python standard
library (http.server + json), so it runs anywhere with no pip install. Storage is
flat JSON files under --data-dir. This is the reference implementation and the seed
for a real deployment; the production service should be a free-tier worker/function
port of these exact endpoints.

Run:
    python server.py --port 8787
Then point the client at it by writing user://community.cfg:
    [service]
    base_url = "http://127.0.0.1:8787"

VALIDATION NOTE: the real catalog-strict validation (known tile/character ids, map
size, defender presence, checksum) lives in the Godot code (MapResource.validate_map
strict + ChallengeCodec.validate) and cannot be fully reproduced here without the game
catalog. This scaffold performs the STRUCTURAL subset (required keys, type, coarse
shape) so the flow is testable; a production port MUST run the full catalog-strict
rules server-side and re-compute the checksum -- never trust the client.
"""

import argparse
import datetime
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PAGE_SIZE = 20
MAX_QUERY_LENGTH = 64
MAX_ACTIVE_BASES = 3
MAX_ATTEMPT_SCORE = 1_000_000
MAX_ATTEMPT_TURNS = 999

# Recommendation weights + scales -- mirror LocalProvider._recommended_score exactly. See
# docs/COMMUNITY_API.md "Recommended feed" for what each term is for.
REC_W_VOTES, REC_W_FAIRNESS, REC_W_ENGAGEMENT, REC_W_FRESHNESS = 0.45, 0.35, 0.12, 0.08
REC_VOTE_SCALE = REC_ATTEMPT_SCALE = 25.0
REC_PEAK_CLEAR_RATE = 0.4
REC_FRESH_HALFLIFE_DAYS = 14.0

_LOCK = threading.Lock()  # serialise file writes across worker threads


# --- Storage ----------------------------------------------------------------

class Store:
    def __init__(self, data_dir):
        self.data_dir = data_dir
        self.payload_dir = os.path.join(data_dir, "payloads")
        os.makedirs(self.payload_dir, exist_ok=True)
        self.index_path = os.path.join(data_dir, "items.json")

    def load_index(self):
        if not os.path.exists(self.index_path):
            return {"items": [], "votes": {}}
        with open(self.index_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        data.setdefault("items", [])
        data.setdefault("votes", {})  # { item_id: { device_id: dir } }
        return data

    def save_index(self, index):
        with open(self.index_path, "w", encoding="utf-8") as f:
            json.dump(index, f, indent="\t")

    def load_payload(self, item_id):
        path = os.path.join(self.payload_dir, _safe(item_id) + ".json")
        if not os.path.exists(path):
            return None
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)

    def save_payload(self, item_id, payload):
        path = os.path.join(self.payload_dir, _safe(item_id) + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent="\t")


def _safe(item_id):
    return "".join(c if (c.isalnum() or c in "_-") else "_" for c in str(item_id))


def _checksum(payload):
    # Deterministic content hash for tamper detection (NOT a signature).
    return str(abs(hash(json.dumps(payload, sort_keys=True))) % (2 ** 31))


def _summary_for(payload, votes, created):
    """Derive an index summary from a payload; return None if unrecognisable.

    `owner` is left blank -- only the upload handler knows the caller's identity, and it
    must come from the request header, never from the payload.
    """
    text = json.dumps(payload)
    if all(k in payload for k in ("format_version", "map", "rules")):
        checksum = str(payload.get("checksum") or _checksum(payload))
        return {
            "id": "challenge_" + checksum, "type": "challenge",
            "name": payload.get("name", "Untitled"), "author": payload.get("author", ""),
            "votes": votes, "attempts": 0, "clears": 0, "owner": "", "active": True,
            "created": created, "size_bytes": len(text), "checksum": checksum,
        }
    if "dimensions" in payload and "layout" in payload:
        checksum = _checksum(payload)
        info = payload.get("map_info") if isinstance(payload.get("map_info"), dict) else {}
        return {
            "id": "map_" + checksum, "type": "map",
            "name": info.get("name", "Untitled Map"), "author": info.get("author", ""),
            "votes": votes, "attempts": 0, "clears": 0, "owner": "", "active": True,
            "created": created, "size_bytes": len(text), "checksum": checksum,
        }
    return None


# --- Boundary sanitisers (mirror CommunityProvider) --------------------------

def _sanitize_query(raw):
    """Trim, cap and lowercase a search needle. '' means NO query."""
    return str(raw or "").strip()[:MAX_QUERY_LENGTH].lower()


def _matches_query(item, needle):
    if not needle:
        return True
    return needle in str(item.get("name", "")).lower() \
        or needle in str(item.get("author", "")).lower()


def _clamp_counter(value, limit):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    try:
        return max(0, min(limit, int(value)))
    except (ValueError, OverflowError):  # NaN / inf
        return 0 if value != value or value < 0 else limit


def _sanitize_outcome(body):
    """Exactly {cleared, score, turns}; unknown keys dropped, numbers clamped."""
    if not isinstance(body, dict):
        body = {}
    cleared = body.get("cleared", False)
    return {
        "cleared": cleared if isinstance(cleared, bool) else False,
        "score": _clamp_counter(body.get("score", 0), MAX_ATTEMPT_SCORE),
        "turns": _clamp_counter(body.get("turns", 0), MAX_ATTEMPT_TURNS),
    }


def _coerce_int(value, fallback=0):
    """An untrusted query/body number as an int. Junk reads as the fallback rather than
    raising -- a malformed `page=abc` is a client mistake to absorb, not a 500 + traceback."""
    if isinstance(value, bool):
        return fallback
    try:
        return int(value)
    except (TypeError, ValueError, OverflowError):
        return fallback


def _is_active(item):
    return bool(item.get("active", True))


def _active_base_count(index, owner):
    if not owner:
        return 0
    return sum(1 for it in index["items"]
               if it.get("owner") == owner and it.get("type") == "challenge" and _is_active(it))


def _created_unix(created):
    try:
        return datetime.datetime.fromisoformat(str(created)).timestamp()
    except (ValueError, TypeError):
        return 0.0


def _recommended_score(item, now):
    """The reference ranking -- documented in docs/COMMUNITY_API.md."""
    v = float(item.get("votes", 0) or 0)
    vote_term = v / (abs(v) + REC_VOTE_SCALE)

    attempts = float(max(0, int(item.get("attempts", 0) or 0)))
    engagement = attempts / (attempts + REC_ATTEMPT_SCALE)

    fairness = 0.0
    if attempts > 0:
        rate = min(1.0, max(0.0, float(max(0, int(item.get("clears", 0) or 0))) / attempts))
        offset = (rate - REC_PEAK_CLEAR_RATE) / REC_PEAK_CLEAR_RATE
        fairness = max(0.0, 1.0 - offset * offset)

    freshness = 0.0
    created = _created_unix(item.get("created", ""))
    if created > 0:
        age_days = max(0.0, (now - created) / 86400.0)
        freshness = 1.0 / (1.0 + age_days / REC_FRESH_HALFLIFE_DAYS)

    return (REC_W_VOTES * vote_term + REC_W_FAIRNESS * fairness
            + REC_W_ENGAGEMENT * engagement + REC_W_FRESHNESS * freshness)


# --- Request handler --------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    store = None  # injected in main()

    def _send(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _device(self):
        return self.headers.get("X-Community-Device", "anonymous")

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return None

    # -- GET --
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        if path == "/v1/items":
            return self._list(parse_qs(parsed.query))
        if path == "/v1/daily":
            return self._daily()
        if path == "/v1/me/bases":
            return self._my_bases()
        if path.startswith("/v1/items/"):
            return self._fetch(path[len("/v1/items/"):])
        self._send(404, {"error": "Not found."})

    # -- POST --
    def do_POST(self):
        path = urlparse(self.path).path.rstrip("/")
        if path == "/v1/items":
            return self._upload()
        for suffix, handler in (("/vote", self._vote), ("/attempts", self._attempt),
                                ("/active", self._set_active)):
            if path.startswith("/v1/items/") and path.endswith(suffix):
                return handler(path[len("/v1/items/"):-len(suffix)])
        self._send(404, {"error": "Not found."})

    # -- Endpoints --
    def _list(self, query):
        sort = (query.get("sort", ["recommended"])[0])
        type_filter = (query.get("type", ["all"])[0])
        page = _coerce_int(query.get("page", ["0"])[0])
        needle = _sanitize_query(query.get("q", [""])[0])
        # Retired bases are invisible to every feed; filters run BEFORE sort + pagination.
        items = [it for it in self.store.load_index()["items"] if _is_active(it)]
        if type_filter not in ("all", ""):
            items = [it for it in items if it.get("type") == type_filter]
        if needle:
            items = [it for it in items if _matches_query(it, needle)]
        if sort == "recommended":
            now = time.time()
            items = sorted(items, key=lambda it: (
                -_recommended_score(it, now), -int(it.get("votes", 0) or 0), str(it.get("id", ""))))
        elif sort == "new":
            items = sorted(items, key=lambda it: it.get("created", ""), reverse=True)
        elif sort == "daily":
            pick = self._daily_id()
            items = sorted(items, key=lambda it: it.get("votes", 0), reverse=True)
            items = [it for it in items if it.get("id") == pick] + \
                    [it for it in items if it.get("id") != pick]
        else:  # top
            items = sorted(items, key=lambda it: it.get("votes", 0), reverse=True)
        start = max(0, page) * PAGE_SIZE
        self._send(200, items[start:start + PAGE_SIZE])

    def _fetch(self, item_id):
        payload = self.store.load_payload(item_id)
        if payload is None:
            return self._send(404, {"error": "Item not found."})
        self._send(200, payload)

    def _upload(self):
        body = self._read_body()
        if body is None:
            return self._send(400, {"error": "Body was not valid JSON."})
        payload = body.get("payload", body)  # accept {payload:...} or a bare payload
        if not isinstance(payload, dict):
            return self._send(400, {"error": "Missing payload object."})
        # STRUCTURAL validation only -- see the module docstring. Server re-derives the
        # checksum and IGNORES any client-supplied one.
        info = payload.get("map_info") if isinstance(payload.get("map_info"), dict) else {}
        created = payload.get("created") or info.get("creation_date", "")
        summary = _summary_for(payload, 0, created)
        if summary is None:
            return self._send(400, {"error": "Payload is neither a map nor a challenge."})
        with _LOCK:
            index = self.store.load_index()
            if any(it.get("id") == summary["id"] for it in index["items"]):
                return self._send(409, {"error": "Item already exists."})
            # Ownership comes from the request header, NEVER from the payload.
            device = self._device()
            summary["owner"] = device
            # The 3-active cap is an invariant: a fourth upload lands retired instead of
            # being refused, so nothing the author made is lost.
            summary["active"] = (summary["type"] != "challenge"
                                 or _active_base_count(index, device) < MAX_ACTIVE_BASES)
            self.store.save_payload(summary["id"], payload)
            index["items"].append(summary)
            self.store.save_index(index)
        self._send(200, summary)

    def _vote(self, item_id):
        body = self._read_body()
        if body is None:
            return self._send(400, {"error": "Body was not valid JSON."})
        direction = max(-1, min(1, _coerce_int(body.get("dir", 0) if isinstance(body, dict) else 0)))
        device = self._device()
        with _LOCK:
            index = self.store.load_index()
            item = next((it for it in index["items"] if it.get("id") == item_id), None)
            if item is None:
                return self._send(404, {"error": "Item not found."})
            votes_map = index["votes"].setdefault(item_id, {})
            prev = int(votes_map.get(device, 0))
            item["votes"] = int(item.get("votes", 0)) + (direction - prev)  # idempotent per device
            if direction == 0:
                votes_map.pop(device, None)
            else:
                votes_map[device] = direction
            self.store.save_index(index)
        self._send(200, {"id": item_id, "votes": item["votes"]})

    def _attempt(self, item_id):
        """Record ONE play. Deliberately not idempotent: every attempt counts, including
        repeats from the same device -- the ledger measures the base, not the audience.
        Retired bases still count (a friend playing from a share code is real traffic)."""
        body = self._read_body()
        if body is None:
            return self._send(400, {"error": "Body was not valid JSON."})
        outcome = _sanitize_outcome(body)
        with _LOCK:
            index = self.store.load_index()
            item = next((it for it in index["items"] if it.get("id") == item_id), None)
            if item is None:
                return self._send(404, {"error": "not_found"})
            item["attempts"] = max(0, int(item.get("attempts", 0) or 0)) + 1
            item["clears"] = max(0, int(item.get("clears", 0) or 0)) + (1 if outcome["cleared"] else 0)
            self.store.save_index(index)
        self._send(200, {"id": item_id, "attempts": item["attempts"],
                         "clears": item["clears"], "outcome": outcome})

    def _my_bases(self):
        device = self._device()
        mine = [it for it in self.store.load_index()["items"]
                if it.get("owner") == device and it.get("type") == "challenge"]
        mine.sort(key=lambda it: str(it.get("created", "")), reverse=True)
        self._send(200, mine)

    def _set_active(self, item_id):
        body = self._read_body()
        if body is None:
            return self._send(400, {"error": "Body was not valid JSON."})
        active = bool(body.get("active", False)) if isinstance(body, dict) else False
        device = self._device()
        with _LOCK:
            index = self.store.load_index()
            item = next((it for it in index["items"] if it.get("id") == item_id), None)
            if item is None:
                return self._send(404, {"error": "not_found"})
            if not device or item.get("owner") != device:
                return self._send(403, {"error": "not_owner"})
            # Only a transition INTO active can breach the cap; retiring always succeeds.
            if (active and not _is_active(item) and item.get("type") == "challenge"
                    and _active_base_count(index, device) >= MAX_ACTIVE_BASES):
                return self._send(409, {"error": "base_limit"})
            item["active"] = active
            self.store.save_index(index)
        self._send(200, {"id": item_id, "active": active})

    def _daily(self):
        self._send(200, {"id": self._daily_id()})

    def _daily_id(self):
        items = [it for it in self.store.load_index()["items"] if _is_active(it)]
        if not items:
            return ""
        seed = datetime.date.today().isoformat()
        return items[abs(hash(seed)) % len(items)].get("id", "")

    def log_message(self, fmt, *args):  # quieter console
        pass


def main():
    parser = argparse.ArgumentParser(description="Conquest community reference server.")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--data-dir", default=os.path.join(os.path.dirname(__file__), "data"))
    args = parser.parse_args()

    Handler.store = Store(args.data_dir)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print("Conquest community server on http://%s:%d  (data: %s)" % (args.host, args.port, args.data_dir))
    print("Point user://community.cfg base_url at that address. Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping.")
        server.shutdown()


if __name__ == "__main__":
    main()
