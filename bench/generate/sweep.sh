#!/usr/bin/env bash
# Time `dagger generate` as the number of managed modules grows.
#
#     bench/generate/sweep.sh 1 2 4 8 12 16 24
#     OBJECTS=10 bench/generate/sweep.sh 8          # 10 objects + 10 enums per module
#
# Each count gets freshly stamped modules, so the engine cannot answer from the
# previous run's cache. Set DAGGER to pick the CLI (e.g. DAGGER="dagger --x-release 1.0.0-beta.11").
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
: "${DAGGER:=dagger}"
: "${OBJECTS:=0}"
logs=bench/generate/logs
mkdir -p "$logs"

printf "%8s  %10s  %14s  %s\n" modules wall generate trace
for n in "$@"; do
  python3 bench/generate/modules.py "$n" --objects "$OBJECTS" >/dev/null
  log="$logs/generate-$n-$OBJECTS.log"
  start=$(date +%s%N)
  $DAGGER -y --progress=plain generate > "$log" 2>&1
  rc=$?
  wall=$(( ($(date +%s%N) - start) / 1000000 ))
  # First occurrence, not last: generate emits the substantive span and then a
  # second one for the post-apply re-check, which is always ~0s.
  span=$(grep -oE "elixir-sdk:generate (DONE|CACHED) \[[0-9.]+m?s" "$log" | head -1 | grep -oE "[0-9.]+m?s$")
  trace=$(grep -oE 'https://dagger.cloud/[^ ]*traces/[0-9a-f]+' "$log" | tail -1)
  [ "$rc" = 0 ] || span="FAILED (rc=$rc, see $log)"
  printf "%8s  %9sms  %14s  %s\n" "$n" "$wall" "$span" "$trace"
done

python3 bench/generate/modules.py --clean >/dev/null
