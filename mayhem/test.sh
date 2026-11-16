#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer oracle for LASlib/LASzip, driven through the prebuilt LAStools CLI
# binaries (mayhem/build-tests/bin, normal flags, no sanitizers). Every check runs a tool on the
# tracked data/test.laz and compares parsed output or a checksum with the value recorded from the
# upstream build; a no-op or exit(0) patch fails them all.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN=mayhem/build-tests/bin
IN=data/test.laz
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
passed=0; failed=0

check() {  # check <name> <expected> <actual>
  if [ "$2" == "$3" ]; then passed=$((passed + 1)); echo "ok   $1"
  else failed=$((failed + 1)); echo "FAIL $1: expected [$2] got [$3]"; fi
}
field() {  # field <regex> : the trimmed value of the first matching lasinfo header line
  grep -E "$1" | head -1 | sed -E 's/^[^:]*:[[:space:]]*//'
}
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

for t in lasinfo laszip las2las lasindex; do
  [ -x "$BIN/$t" ] || { echo "missing $BIN/$t: mayhem/build.sh did not build it" >&2; emit_ctrf lastools 0 1 0; exit 1; }
done

# lasinfo parses the LAZ header and every point (decompressing through LASzip)
INFO=$("$BIN/lasinfo" -i "$IN" -stdout 2>&1)
check "lasinfo version"        "1.2"                               "$(field 'version major.minor' <<<"$INFO")"
check "lasinfo point format"   "1"                                 "$(field 'point data format' <<<"$INFO")"
check "lasinfo point count"    "2690"                              "$(field 'number of point records' <<<"$INFO")"
check "lasinfo returns"        "2413 277 0 0 0"                    "$(field 'number of points by return' <<<"$INFO")"
check "lasinfo min xyz"        "476941.35 4366469.50 2726.66"      "$(field 'min x y z' <<<"$INFO")"
check "lasinfo max xyz"        "477208.56 4366726.48 2750.90"      "$(field 'max x y z' <<<"$INFO")"
check "lasinfo gps_time range" "70291.106000 71058.508200"         "$(grep -E '^[[:space:]]+gps_time' <<<"$INFO" | sed -E 's/^[[:space:]]+gps_time[[:space:]]+//')"

# laszip: LAZ -> LAS decompression is byte-exact, and re-compression round-trips
"$BIN/laszip" -i "$IN" -o "$W/a.las" >/dev/null 2>&1
check "laszip decompressed size"   "75549" "$(stat -c %s "$W/a.las" 2>/dev/null)"
check "laszip decompressed sha256" "ae597653494c86d8107b169e9c7c1e94c84ee09e15302da1bdd925d9fd0e4d3f" "$(sha "$W/a.las")"
"$BIN/laszip" -i "$W/a.las" -o "$W/b.laz" >/dev/null 2>&1
"$BIN/laszip" -i "$W/b.laz" -o "$W/c.las" >/dev/null 2>&1
check "laszip round-trip sha256"   "ae597653494c86d8107b169e9c7c1e94c84ee09e15302da1bdd925d9fd0e4d3f" "$(sha "$W/c.las")"

# las2las: point selection and filtering, verified by reading the result back
"$BIN/las2las" -i "$IN" -keep_every_nth 200 -o "$W/n.las" >/dev/null 2>&1
NINFO=$("$BIN/lasinfo" -i "$W/n.las" -stdout 2>&1)
check "las2las nth count"  "13"                           "$(field 'number of point records' <<<"$NINFO")"
check "las2las nth min"    "476952.55 4366474.02 2735.41" "$(field 'min x y z' <<<"$NINFO")"
check "las2las nth max"    "477195.82 4366694.07 2741.84" "$(field 'max x y z' <<<"$NINFO")"
"$BIN/las2las" -i "$IN" -keep_class 3 -drop_return 2 -o "$W/r.las" >/dev/null 2>&1
RINFO=$("$BIN/lasinfo" -i "$W/r.las" -stdout -nv 2>&1)
check "las2las filter count"   "2413"           "$(field 'number of point records' <<<"$RINFO")"
check "las2las filter returns" "2413 0 0 0 0"    "$(field 'number of points by return' <<<"$RINFO")"

# lasindex: the LAX spatial index written for the decompressed file is byte-exact
"$BIN/lasindex" -i "$W/a.las" >/dev/null 2>&1
check "lasindex magic"  "LASX" "$(head -c4 "$W/a.lax" 2>/dev/null)"
check "lasindex sha256" "37c8c4fdfdc2d51180839c100caadd8bc4b95fbddaaf160c87dd1687757f2a5b" "$(sha "$W/a.lax")"

emit_ctrf lastools "$passed" "$failed" 0
