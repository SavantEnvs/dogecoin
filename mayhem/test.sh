#!/usr/bin/env bash
# Runs dogecoin's own Boost.Test suite (test_dogecoin, built by mayhem/build.sh) and reports CTRF.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

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

RUNNER="$SRC/mayhem/build-test/src/test/test_dogecoin"
[ -x "$RUNNER" ] || { echo "test_dogecoin missing: mayhem/build.sh must build it" >&2; emit_ctrf boost-test 0 1; exit 1; }

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
cd "$SRC/mayhem/build-test/src"
"$RUNNER" --report_level=detailed --log_level=error > "$OUT" 2>&1
rc=$?
cat "$OUT"

# Count leaf test cases from Boost's detailed report; every case the runner announced must be accounted
# for, so a neutered/empty runner (no report at all) is a failure, never "0 failures".
expected="$(sed -n 's/^Running \([0-9][0-9]*\) test case.*/\1/p' "$OUT" | head -1)"
passed="$(grep -c '^ *Test case ".*" has passed' "$OUT")"
failed="$(grep -c '^ *Test case ".*" has failed' "$OUT")"
skipped="$(grep -c '^ *Test case ".*" \(is\|was\) skipped' "$OUT")"
if [ -z "$expected" ] || [ "$expected" -eq 0 ] || [ "$passed" -eq 0 ] || \
   [ $((passed + failed + skipped)) -ne "$expected" ]; then
  echo "test_dogecoin produced no usable report (expected=${expected:-none} passed=$passed failed=$failed rc=$rc)" >&2
  emit_ctrf boost-test "$passed" $((failed > 0 ? failed : 1)) "$skipped"
  exit 1
fi
[ "$rc" -eq 0 ] || failed=$((failed > 0 ? failed : 1))
emit_ctrf boost-test "$passed" "$failed" "$skipped"
