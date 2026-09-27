extends RefCounted
class_name NetCommitReveal

## Commit-reveal randomness for a network match (see systems/net/README.md,
## "Unpredictable, unriggable combat RNG").
##
## Every CONTRIBUTOR (the host / server and, by default, every seated client)
## owns a secret SHA-256 HASH CHAIN:
##
##     h_0 = S (32 secret random bytes),  h_{i+1} = sha256(h_i),  i < N
##
## and at match start publishes only its ANCHOR h_N (the commitment). The share
## it contributes to accepted action number k of the current EPOCH (k = 1..N) is
## h_{N-k}: revealing it discloses nothing about h_{N-k-1} (SHA-256 is one-way),
## and anyone can verify it with sha256(h_{N-k}) == h_{N-k+1}, the previously
## verified value (the anchor for k = 1). So a contributor's whole future
## sequence of shares is FIXED at commit time (no grinding / biasing) yet
## UNKNOWN to everyone else until it reveals each one.
##
## The randomness for action seq is
##
##     seed(seq) = first 8 bytes of sha256( share_c1 || share_c2 || ... || seq )
##
## over the contributors in ascending peer-id order. It is uniformly random as
## long as ONE contributor is honest, and nobody can compute it before every
## contributor has revealed -- which NetSession only lets happen AFTER the action
## consuming it was irrevocably accepted (see NetSession, "RNG round").
##
## Chains are finite: the reveal for the LAST index of an epoch carries the
## anchor of the contributor's next chain ("next"), committed before any of its
## values is revealed, so a match can run forever with O(N) memory.
##
## This class is pure bookkeeping + crypto: no networking, fully deterministic
## given the secrets, unit-testable.

const HASH_BYTES := 32
const DEFAULT_CHAIN_LENGTH := 4096
const MIN_CHAIN_LENGTH := 2
const MAX_CHAIN_LENGTH := 65536

## Share dictionary keys (what goes on the wire for one contributor + seq).
const K_REVEAL := "r"
const K_NEXT := "n"

var chain_length: int = DEFAULT_CHAIN_LENGTH
## Sorted peer ids of every contributor.
var contributors: Array = []
## Our peer id, or -1 when we only verify (not a contributor).
var local_peer: int = -1

# Our own chain for the current epoch: _chain[i] = h_i, i = 0..N. And the next
# epoch's chain, generated when we reveal our last share of this one.
var _chain: Array = []
var _next_chain: Array = []
# Per contributor: last verified chain value (anchor at epoch start), the last
# seq it revealed, and its committed next-epoch anchor.
var _last_value: Dictionary = {}
var _last_seq: Dictionary = {}
var _next_anchor: Dictionary = {}
# seq -> {peer: verified share dict} for rounds still being assembled.
var _round: Dictionary = {}
## Secret source (tests inject a deterministic one): Callable() -> PackedByteArray(32).
var secret_source: Callable = Callable()


func _init(p_chain_length: int = DEFAULT_CHAIN_LENGTH) -> void:
	chain_length = clampi(p_chain_length, MIN_CHAIN_LENGTH, MAX_CHAIN_LENGTH)


# ---------------------------------------------------------------------------
# Hashing helpers
# ---------------------------------------------------------------------------

static func h(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()


static func is_hash(v) -> bool:
	return v is PackedByteArray and v.size() == HASH_BYTES


func _new_secret() -> PackedByteArray:
	if secret_source.is_valid():
		var s = secret_source.call()
		if is_hash(s):
			return s
	return Crypto.new().generate_random_bytes(HASH_BYTES)


## Build a chain h_0..h_N from a fresh secret.
func _build_chain() -> Array:
	var c: Array = [_new_secret()]
	for i in range(chain_length):
		c.append(h(c[i]))
	return c


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Start a match. [param p_contributors] are peer ids; if [param p_local_peer]
## is among them a secret chain is generated and its anchor returned (else an
## empty array: we only verify).
func begin(p_local_peer: int, p_contributors: Array) -> PackedByteArray:
	local_peer = p_local_peer
	contributors = p_contributors.duplicate()
	contributors.sort()
	_chain.clear()
	_next_chain.clear()
	_last_value.clear()
	_last_seq.clear()
	_next_anchor.clear()
	_round.clear()
	if is_contributor(local_peer):
		_chain = _build_chain()
		_last_value[local_peer] = own_anchor()
		_last_seq[local_peer] = 0
		return own_anchor()
	return PackedByteArray()


func is_contributor(peer_id: int) -> bool:
	return contributors.has(peer_id)


func own_anchor() -> PackedByteArray:
	return _chain[chain_length] if _chain.size() == chain_length + 1 else PackedByteArray()


## Record [param peer_id]'s commitment. Returns false (and ignores it) when it
## is malformed, from a non-contributor, or would REPLACE an anchor already set.
func set_anchor(peer_id: int, anchor) -> bool:
	if not is_contributor(peer_id) or not is_hash(anchor):
		return false
	if _last_value.has(peer_id):
		# Re-announcing the SAME commitment is fine; changing it never is.
		return int(_last_seq.get(peer_id, 0)) == 0 and _last_value[peer_id] == anchor
	_last_value[peer_id] = anchor
	_last_seq[peer_id] = 0
	return true


## True once every contributor's anchor is known.
func has_all_anchors() -> bool:
	for p in contributors:
		if not _last_value.has(p):
			return false
	return true


func anchors() -> Dictionary:
	var out := {}
	for p in contributors:
		if _last_value.has(p) and int(_last_seq.get(p, 0)) == 0:
			out[p] = _last_value[p]
	return out


## Seed for anything rolled BEFORE the first accepted action (turn-1 start
## ticks): derived from the published anchors. See README for its (tiny) caveat.
func setup_seed() -> int:
	var buf := PackedByteArray()
	for p in contributors:
		buf.append_array(_last_value.get(p, PackedByteArray()))
	buf.append_array("setup".to_utf8_buffer())
	return h(buf).decode_s64(0)


# ---------------------------------------------------------------------------
# Per-action shares
# ---------------------------------------------------------------------------

## Index of [param seq] inside its epoch, 1..N.
func index_of(seq: int) -> int:
	return ((seq - 1) % chain_length) + 1


## Our share for accepted action [param seq] (must be requested in order).
## {r: h_{N-k}} plus, at the last index of an epoch, {n: next epoch's anchor}.
func own_share(seq: int) -> Dictionary:
	if not is_contributor(local_peer) or seq < 1:
		return {}
	var k := index_of(seq)
	var share := {K_REVEAL: _chain[chain_length - k]}
	if k == chain_length:
		if _next_chain.is_empty():
			_next_chain = _build_chain()
		share[K_NEXT] = _next_chain[chain_length]
	return share


## Verify and record [param peer_id]'s share for [param seq]. Returns "" when
## valid, else a reason ("not_contributor", "out_of_order", "malformed",
## "bad_reveal", "missing_next_anchor"). A share must extend the peer's chain by
## exactly one step: sha256(reveal) == the last value verified for it.
func accept_share(peer_id: int, seq: int, share) -> String:
	if not is_contributor(peer_id):
		return "not_contributor"
	if not (share is Dictionary) or not is_hash(share.get(K_REVEAL)):
		return "malformed"
	if seq != int(_last_seq.get(peer_id, -1)) + 1 or not _last_value.has(peer_id):
		return "out_of_order"
	var reveal: PackedByteArray = share[K_REVEAL]
	if h(reveal) != _last_value[peer_id]:
		return "bad_reveal"
	var k := index_of(seq)
	if k == chain_length:
		if not is_hash(share.get(K_NEXT)):
			return "missing_next_anchor"
		_next_anchor[peer_id] = share[K_NEXT]
	# Commit the step.
	_last_seq[peer_id] = seq
	if k == chain_length:
		_last_value[peer_id] = _next_anchor[peer_id]
		_next_anchor.erase(peer_id)
		if peer_id == local_peer:
			_chain = _next_chain
			_next_chain = []
	else:
		_last_value[peer_id] = reveal
	if not _round.has(seq):
		_round[seq] = {}
	var stored := {K_REVEAL: reveal}
	if share.has(K_NEXT):
		stored[K_NEXT] = share[K_NEXT]
	_round[seq][peer_id] = stored
	return ""


## Record OUR OWN share for [param seq] (we trust ourselves; still verified).
func accept_own(seq: int, share: Dictionary) -> String:
	return accept_share(local_peer, seq, share)


## True when every contributor's share for [param seq] was verified.
func has_round(seq: int) -> bool:
	var r: Dictionary = _round.get(seq, {})
	for p in contributors:
		if not r.has(p):
			return false
	return true


## True once [param peer_id]'s share for [param seq] was verified.
func has_share(peer_id: int, seq: int) -> bool:
	return _round.get(seq, {}).has(peer_id)


## The 64-bit RNG seed for [param seq]; only defined once [method has_round].
## Returns [code]null[/code] before that (the value is NOT derivable yet).
func seed_for(seq: int):
	if not has_round(seq):
		return null
	var buf := PackedByteArray()
	for p in contributors:
		buf.append_array(_round[seq][p][K_REVEAL])
	var s := PackedByteArray()
	s.resize(8)
	s.encode_s64(0, seq)
	buf.append_array(s)
	return h(buf).decode_s64(0)


## [param peer_id]'s verified share for [param seq] ({} if none).
func share_of(peer_id: int, seq: int) -> Dictionary:
	return _round.get(seq, {}).get(peer_id, {})


## Forget the assembled round for [param seq] (after it was applied).
func consume(seq: int) -> void:
	_round.erase(seq)


## The last seq whose share [param peer_id] revealed (0 = none yet).
func last_seq_of(peer_id: int) -> int:
	return int(_last_seq.get(peer_id, 0))
