#!/usr/bin/env bash
# lacc/mayhem/test.sh — RUN lacc's OWN test suite (test/check.sh) against the normal-flags lacc that
# mayhem/build.sh produced → CTRF. PATCH-grade oracle: it never compiles lacc itself.
#
# test/check.sh is a DIFFERENTIAL / golden-output harness: for each test/<cat>/*.c it compiles the file
# with lacc (in -E, -S, -c and -c -O1 modes), assembles+links the result with the REFERENCE compiler
# (gcc), RUNS the produced program, and asserts BOTH the exit status AND the stdout match what the same
# program built by gcc produces. It is a KNOWN-ANSWER suite — it asserts lacc compiles each program to
# something that behaves identically to the reference, not merely that lacc exits 0. A no-op / exit(0)
# "patch" to lacc emits no/garbage assembly and FAILS the diff, so it can't reward-hack this oracle.
#
# We run the C-language conformance dirs (c89, c99, c11) — pure standard C programs that need only gcc
# as the reference + linker. (The Makefile's `all` also does a self-host bootstrap that diffs .o files
# byte-for-byte across two builds; that is sensitive to the host cc and not a behavior oracle, so we
# drive check.sh directly over the source dirs instead.)
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
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

LACC="$SRC/build-tests/lacc"
[ -x "$LACC" ] || { echo "missing $LACC — run mayhem/build.sh first" >&2; exit 2; }
command -v gcc >/dev/null 2>&1 || { echo "gcc (reference compiler) not found" >&2; exit 2; }

# check.sh resolves its builtin headers relative to where bin/lacc lives, via the LIB_PATH baked at
# configure time (build.sh installed the test build under build-tests/install). Run from test/ as the
# Makefile does. BIN is a scratch output dir.
cd "$SRC/test"
BIN="$SRC/build-tests/checkbin"
rm -rf "$BIN"; mkdir -p "$BIN"

passed=0; failed=0
for cat in c89 c99 c11; do
  for f in $(find "$cat" -maxdepth 1 -type f -iname '*.c' | sort); do
    if sh ./check.sh "$LACC -std=$cat" "$f" "gcc -std=$cat -w -Wno-psabi" "$BIN" >/dev/null 2>&1; then
      passed=$((passed+1))
    else
      failed=$((failed+1))
      echo "FAIL: $f" >&2
    fi
  done
done

echo "lacc check.sh: passed=$passed failed=$failed" >&2
emit_ctrf "lacc-check" "$passed" "$failed"
