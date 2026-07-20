#!/usr/bin/env bash
# Re-export sculpts through the Blender -> Godot pipeline.
#
# A .glb is a DERIVED artifact: editing the .blend changes nothing until it is
# re-exported. This reads tools/blender/assets.conf so that re-export is one
# command rather than a remembered flag string.
#
#   tools/blender/reingest.sh              # every asset whose .blend is newer
#   tools/blender/reingest.sh --all        # every asset, regardless of timestamps
#   tools/blender/reingest.sh tree_grunt   # just this one
#
# Everything downstream survives: the CharacterResource references the .glb by
# path, and Godot's .import settings file persists -- so stats, id and footprint
# are all preserved and Godot re-imports the new mesh on its own.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$REPO/tools/blender/assets.conf"
SCRIPT="$REPO/tools/blender/prepare_unit.py"

# Blender location: override with BLENDER=/path/to/blender.
if [ -z "${BLENDER:-}" ]; then
  BLENDER="$(ls -d "/c/Program Files/Blender Foundation"/*/blender.exe 2>/dev/null | tail -1)"
fi
if [ ! -f "$BLENDER" ]; then
  echo "ERROR: Blender not found. Set BLENDER=/path/to/blender.exe" >&2
  exit 1
fi

[ -f "$CONF" ] || { echo "ERROR: missing $CONF" >&2; exit 1; }

FORCE=0
ONLY=""
case "${1:-}" in
  --all) FORCE=1 ;;
  "")    ;;
  *)     ONLY="$1" ;;
esac

processed=0
skipped=0

while IFS='|' read -r name src out height faces extra; do
  # Skip comments and blank lines.
  case "${name:-}" in ''|\#*) continue ;; esac
  name="$(echo "$name" | xargs)"
  src="$(echo "$src" | xargs)"
  out="$(echo "$out" | xargs)"
  height="$(echo "$height" | xargs)"
  faces="$(echo "$faces" | xargs)"
  # Optional 6th column: extra prepare_unit.py flags (e.g. "--thorns 40").
  # Without this, a rebuild silently dropped per-asset options -- petalfang came
  # back SMOOTH, losing every thorn, with nothing in the output to say so.
  extra="$(echo "${extra:-}" | xargs)"

  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue

  if [ ! -f "$src" ]; then
    echo "SKIP  $name -- source not found: $src" >&2
    skipped=$((skipped+1))
    continue
  fi

  abs_out="$REPO/$out"
  # Only rebuild when the sculpt is newer than the export, unless forced. This is
  # what makes the no-argument form cheap to run habitually.
  if [ "$FORCE" -eq 0 ] && [ -f "$abs_out" ] && [ "$src" -ot "$abs_out" ]; then
    echo "FRESH $name -- .glb is newer than the .blend, skipping"
    skipped=$((skipped+1))
    continue
  fi

  echo "BUILD $name  ($src -> $out)${extra:+  [$extra]}"
  mkdir -p "$(dirname "$abs_out")"
  # $extra is intentionally UNQUOTED so "--thorns 40" splits into two arguments.
  "$BLENDER" --background "$src" --factory-startup --python "$SCRIPT" -- \
      --output "$abs_out" --name "$name" \
      --target-height "$height" --target-faces "$faces" $extra 2>&1 \
    | grep -E "^PIPELINE" | sed 's/^PIPELINE/      /'
  processed=$((processed+1))
done < "$CONF"

echo "----"
echo "rebuilt=$processed skipped=$skipped"
if [ "$processed" -gt 0 ]; then
  echo "Godot will re-import the changed .glb files on next focus/launch."
fi
