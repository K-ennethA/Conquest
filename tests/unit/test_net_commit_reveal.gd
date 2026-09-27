extends GutTest

## NetCommitReveal: hash-chain commitments, share verification, epoch re-commit
## and seed derivation -- pure, no networking. Two / three instances play the
## roles of the peers and exchange shares by hand.

const HOST := 1
const CLIENT := 7


func _pair(length: int) -> Array:
	var host := NetCommitReveal.new(length)
	var client := NetCommitReveal.new(length)
	var ha := host.begin(HOST, [HOST, CLIENT])
	var ca := client.begin(CLIENT, [CLIENT, HOST])
	assert_true(host.set_anchor(CLIENT, ca), "host records client anchor")
	assert_true(client.set_anchor(HOST, ha), "client records host anchor")
	return [host, client]


## One full round: both reveal, both verify the other's share. Returns seeds.
func _round(host: NetCommitReveal, client: NetCommitReveal, seq: int) -> Array:
	var hs := host.own_share(seq)
	assert_eq(host.accept_own(seq, hs), "", "host own share %d" % seq)
	assert_eq(client.accept_share(HOST, seq, hs), "", "client verifies host share %d" % seq)
	var cs := client.own_share(seq)
	assert_eq(client.accept_own(seq, cs), "", "client own share %d" % seq)
	assert_eq(host.accept_share(CLIENT, seq, cs), "", "host verifies client share %d" % seq)
	var out := [host.seed_for(seq), client.seed_for(seq)]
	host.consume(seq)
	client.consume(seq)
	return out


func test_anchor_is_a_hash_and_shares_verify_against_it() -> void:
	var p := _pair(16)
	assert_eq(p[0].own_anchor().size(), 32, "sha256 anchor")
	for seq in range(1, 6):
		var seeds := _round(p[0], p[1], seq)
		assert_not_null(seeds[0], "seed defined once both revealed")
		assert_eq(seeds[0], seeds[1], "both peers derive the same seed for %d" % seq)


func test_seed_is_unknown_until_every_contributor_revealed() -> void:
	var p: Array = _pair(16)
	var host: NetCommitReveal = p[0]
	var client: NetCommitReveal = p[1]
	var hs := host.own_share(1)
	host.accept_own(1, hs)
	client.accept_share(HOST, 1, hs)
	assert_null(host.seed_for(1), "host (e.g. the actor) cannot derive the roll from its own share alone")
	var cs := client.own_share(1)
	client.accept_own(1, cs)
	assert_not_null(client.seed_for(1), "client has both shares")
	assert_null(host.seed_for(1), "still unknown to the host until the client's reveal arrives")
	# The anchor / previous reveals do not give the next reveal away: hashing
	# forward only walks back toward the anchor.
	var next_client := client.own_share(2)[NetCommitReveal.K_REVEAL] as PackedByteArray
	assert_ne(NetCommitReveal.h(cs[NetCommitReveal.K_REVEAL]), next_client, "future share is not a hash of the past")
	assert_eq(NetCommitReveal.h(next_client), cs[NetCommitReveal.K_REVEAL], "...but verifies against it once revealed")
	host.accept_share(CLIENT, 1, cs)
	assert_eq(host.seed_for(1), client.seed_for(1), "agreed")


func test_tampered_share_is_rejected() -> void:
	var p: Array = _pair(16)
	var host: NetCommitReveal = p[0]
	var client: NetCommitReveal = p[1]
	var hs := host.own_share(1)
	host.accept_own(1, hs)
	client.accept_share(HOST, 1, hs)
	var cs := client.own_share(1)
	var bad: Dictionary = cs.duplicate(true)
	var r: PackedByteArray = bad[NetCommitReveal.K_REVEAL].duplicate()
	r[5] = r[5] ^ 0x80
	bad[NetCommitReveal.K_REVEAL] = r
	assert_eq(host.accept_share(CLIENT, 1, bad), "bad_reveal", "one flipped bit is caught")
	assert_eq(host.accept_share(CLIENT, 1, {"r": PackedByteArray([1, 2])}), "malformed", "short share")
	assert_eq(host.accept_share(CLIENT, 2, cs), "out_of_order", "wrong seq")
	assert_eq(host.accept_share(99, 1, cs), "not_contributor", "stranger")
	assert_eq(host.accept_share(CLIENT, 1, cs), "", "the honest share still verifies")
	assert_eq(host.accept_share(CLIENT, 1, cs), "out_of_order", "replay refused")


func test_random_bytes_cannot_be_passed_off_as_a_share() -> void:
	var p: Array = _pair(16)
	var fake := {NetCommitReveal.K_REVEAL: Crypto.new().generate_random_bytes(32)}
	assert_eq(p[0].accept_share(CLIENT, 1, fake), "bad_reveal", "a share must extend the committed chain")


func test_commitment_cannot_be_changed() -> void:
	var p: Array = _pair(16)
	var other := NetCommitReveal.new(16)
	var new_anchor := other.begin(CLIENT, [CLIENT])
	assert_false(p[0].set_anchor(CLIENT, new_anchor), "a second, different anchor is refused")
	assert_true(p[0].set_anchor(CLIENT, p[1].own_anchor()), "re-announcing the same one is fine")


func test_chain_recommits_across_epochs() -> void:
	var p: Array = _pair(3)
	var seeds: Array = []
	for seq in range(1, 11):   # > 3 epochs of length 3
		var s := _round(p[0], p[1], seq)
		assert_eq(s[0], s[1], "agree at %d" % seq)
		seeds.append(s[0])
	var uniq := {}
	for s in seeds:
		uniq[s] = true
	assert_eq(uniq.size(), seeds.size(), "every action got a fresh seed")


func test_last_index_share_must_carry_next_anchor() -> void:
	var p: Array = _pair(2)
	_round(p[0], p[1], 1)
	var hs: Dictionary = p[0].own_share(2)
	assert_true(hs.has(NetCommitReveal.K_NEXT), "epoch-end share carries the next anchor")
	var stripped := {NetCommitReveal.K_REVEAL: hs[NetCommitReveal.K_REVEAL]}
	assert_eq(p[1].accept_share(HOST, 2, stripped), "missing_next_anchor", "refused without it")


func test_seed_depends_on_every_share() -> void:
	# Same host secret, different client secrets -> different seeds.
	var fixed := func(): return PackedByteArray(range(32))
	var seeds := []
	for i in range(2):
		var host := NetCommitReveal.new(8)
		host.secret_source = fixed
		var client := NetCommitReveal.new(8)
		var ha := host.begin(HOST, [HOST, CLIENT])
		var ca := client.begin(CLIENT, [HOST, CLIENT])
		host.set_anchor(CLIENT, ca)
		client.set_anchor(HOST, ha)
		seeds.append(_round(host, client, 1)[0])
	assert_ne(seeds[0], seeds[1], "a host that fixes its own chain still cannot fix the outcome")


func test_three_contributors() -> void:
	var ids := [1, 5, 9]
	var peers := []
	var anchors := {}
	for id in ids:
		var c := NetCommitReveal.new(4)
		anchors[id] = c.begin(id, ids)
		peers.append(c)
	for c in peers:
		for id in ids:
			assert_true(c.set_anchor(id, anchors[id]), "anchor %d" % id)
	for seq in range(1, 9):
		var shares := {}
		for i in range(3):
			shares[ids[i]] = peers[i].own_share(seq)
		for i in range(3):
			for id in ids:
				assert_eq(peers[i].accept_share(id, seq, shares[id]), "", "peer %d verifies %d@%d" % [ids[i], id, seq])
		assert_eq(peers[0].seed_for(seq), peers[1].seed_for(seq), "agree %d" % seq)
		assert_eq(peers[1].seed_for(seq), peers[2].seed_for(seq), "agree %d" % seq)
		for c in peers:
			c.consume(seq)
