#!/usr/bin/env bash
# Multi-process network check: ONE headless dedicated server + TWO headless
# scripted clients (dev_scripts/net_bot_client.gd), real ENet over 127.0.0.1,
# each process running the full GameWorld. Passes when all three report the same
# final (seq, state digest), no desync and no randomness-verification failure.
#
#   GODOT=/path/to/godot dev_scripts/net_multiprocess_check.sh [map] [turn_system] [actions] [rng]
#
# Defaults: default_skirmish, traditional, 40 actions, rng=all. Run from the
# project root (after `godot --headless --import .`). HOSTED=1 runs the
# player-hosted variant instead (host bot = listen server + seat 0, guest bot).
# MODE=duel runs an ONLINE DUEL instead of a map battle (the map / turn system are then
# ignored; UNIT_A / UNIT_B pick the two combatants, default: each slot's default unit):
#
#   GODOT=... MODE=duel dev_scripts/net_multiprocess_check.sh "" "" 60
#
# IDLE=N runs the TURN-CLOCK check: the second bot (BotB / the guest) sits out its first N
# timed turns, so the host / server times it out (a timeout is a normal accepted action);
# every timed turn gets CLOCK_MS ms (default 1500). Passes when the final states still agree
# AND the idle bot saw at least one timeout. Keep N below the forfeit limit (3) to play on.
set -u
GODOT="${GODOT:-godot}"
MAP="${1:-res://game/maps/resources/default_skirmish.tres}"
TURNS="${2:-traditional}"
ACTIONS="${3:-40}"
RNG="${4:-all}"
PORT="${PORT:-$((20000 + RANDOM % 20000))}"
OUT="${OUT:-$(mktemp -d)}"
TIMEOUT="${TIMEOUT:-240}"
MODE="${MODE:-conquest}"
MODE_ARGS="--mode $MODE"
UNIT_A_ARGS=""; [ -n "${UNIT_A:-}" ] && UNIT_A_ARGS="--unit $UNIT_A"
UNIT_B_ARGS=""; [ -n "${UNIT_B:-}" ] && UNIT_B_ARGS="--unit $UNIT_B"
IDLE="${IDLE:-0}"
CLOCK_ARGS=""; IDLE_ARGS=""
if [ "$IDLE" -gt 0 ]; then
	CLOCK_ARGS="--turn-clock-ms ${CLOCK_MS:-1500}"
	IDLE_ARGS="--idle-turns $IDLE"
fi
# The idle bot must have seen the host time it out (IDLE mode only).
timeouts_ok() {
	[ "$IDLE" -gt 0 ] || return 0
	local n; n=$(echo "$1" | grep -o 'timeouts=[0-9]*' | grep -o '[0-9]*')
	[ -n "$n" ] && [ "$n" -gt 0 ]
}

if [ "${HOSTED:-0}" = "1" ]; then
	# PLAYER-HOSTED variant: a host bot (listen server + seat 0) and a guest bot.
	echo "net check (player-hosted): mode=$MODE map=$MAP turns=$TURNS actions=$ACTIONS idle=$IDLE port=$PORT logs=$OUT"
	timeout "$TIMEOUT" "$GODOT" --headless --path . -- --net-bot --host --port "$PORT" --name Host $MODE_ARGS $UNIT_A_ARGS \
		--map "$MAP" --turn-system "$TURNS" --end-after-actions "$ACTIONS" $CLOCK_ARGS > "$OUT/host.log" 2>&1 &
	H=$!
	sleep 2
	timeout "$TIMEOUT" "$GODOT" --headless --path . -- --net-bot --connect 127.0.0.1 --port "$PORT" --name Guest $MODE_ARGS $UNIT_B_ARGS $IDLE_ARGS \
		> "$OUT/guest.log" 2>&1
	RG=$?
	wait $H; RH=$?
	HF=$(grep -o 'FINAL .*' "$OUT/host.log" | head -1); GF=$(grep -o 'FINAL .*' "$OUT/guest.log" | head -1)
	echo "host : $HF (exit $RH)"; echo "guest: $GF (exit $RG)"
	KH=$(echo "$HF" | grep -o 'seq=[0-9]* digest=-\?[0-9]*'); KG=$(echo "$GF" | grep -o 'seq=[0-9]* digest=-\?[0-9]*')
	if [ -n "$KH" ] && [ "$KH" = "$KG" ] && [ $RH -eq 0 ] && [ $RG -eq 0 ] && timeouts_ok "$GF"; then
		echo "PASS: identical final state on host and guest ($KH)"; exit 0
	fi
	echo "FAIL (see $OUT)"; exit 1
fi

echo "net check: mode=$MODE map=$MAP turns=$TURNS actions=$ACTIONS rng=$RNG idle=$IDLE port=$PORT logs=$OUT"
timeout "$TIMEOUT" "$GODOT" --headless --path . -- --server --port "$PORT" $MODE_ARGS --map "$MAP" \
	--turn-system "$TURNS" --rng "$RNG" --max-matches 1 --end-after-actions "$ACTIONS" $CLOCK_ARGS \
	> "$OUT/server.log" 2>&1 &
SRV=$!
sleep 3
timeout "$TIMEOUT" "$GODOT" --headless --path . -- --net-bot --connect 127.0.0.1 --port "$PORT" --name BotA $MODE_ARGS $UNIT_A_ARGS \
	> "$OUT/bot_a.log" 2>&1 &
A=$!
sleep 1
timeout "$TIMEOUT" "$GODOT" --headless --path . -- --net-bot --connect 127.0.0.1 --port "$PORT" --name BotB $MODE_ARGS $UNIT_B_ARGS $IDLE_ARGS \
	> "$OUT/bot_b.log" 2>&1 &
B=$!
wait $A; RA=$?
wait $B; RB=$?
wait $SRV; RS=$?

S_FINAL=$(grep -o 'FINAL .*' "$OUT/server.log" | head -1)
A_FINAL=$(grep -o 'FINAL .*' "$OUT/bot_a.log" | head -1)
B_FINAL=$(grep -o 'FINAL .*' "$OUT/bot_b.log" | head -1)
echo "server: $S_FINAL (exit $RS)"
echo "bot A : $A_FINAL (exit $RA)"
echo "bot B : $B_FINAL (exit $RB)"

key() { echo "$1" | grep -o 'seq=[0-9]* digest=-\?[0-9]*'; }
KS=$(key "$S_FINAL"); KA=$(key "$A_FINAL"); KB=$(key "$B_FINAL")
if [ -n "$KS" ] && [ "$KS" = "$KA" ] && [ "$KA" = "$KB" ] && [ $RA -eq 0 ] && [ $RB -eq 0 ] && [ $RS -eq 0 ] \
		&& timeouts_ok "$B_FINAL"; then
	echo "PASS: identical final state on server and both clients ($KS)"
	exit 0
fi
echo "FAIL (see $OUT)"
exit 1
