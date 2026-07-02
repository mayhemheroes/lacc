#!/usr/bin/env bash
# lacc/mayhem/build.sh — build lacc (a small self-hosting C compiler) as the fuzz target, plus a
# clean normal-flags build of the same compiler for lacc's own golden-output test suite (mayhem/test.sh).
#
# lacc builds via amalgamation: `./configure && make` compiles src/lacc.c (-DAMALGAMATION, the whole
# front end — preprocessor, scanner, parser, decl/expr/stmt/type analysis — plus the x86_64 backend)
# into bin/lacc. No external deps. The Mayhem target is FILE-INPUT (CLI): `lacc -S @@ -o /dev/null`
# runs the compiler on the fuzz bytes as a C source file and emits assembly to /dev/null (parse +
# codegen, but no external assembler/linker). The natural fuzz surface is the compiler itself on a
# source file — no libFuzzer harness.
#
# lacc bakes LIB_PATH / INCLUDE_PATHS into config.h at configure time (where it finds its own
# freestanding headers — stdarg.h, stddef.h, … — and the system include dirs). We `make install` each
# build into a prefix so those headers resolve at runtime, exactly as a normal lacc install would.
#
# Two builds from the same (in-tree) source tree, done sequentially (configure writes config.h/config.mak
# at the repo root; the Makefile builds in-tree, so the builds can't coexist in one objdir):
#   (1) NORMAL-flags build -> /mayhem/build-tests/install  (honest oracle for test.sh; no sanitizer noise)
#   (2) SANITIZED build     -> /mayhem/lacc (the fuzz target) + /mayhem/install (its lib/include prefix)
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit empty value
# (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (the compiler's natural crash). lacc
# has no external libs to link, so the empty-sanitizer build links cleanly with no extra flags.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC MAYHEM_JOBS

cd "$SRC"

# lacc's configure defaults CFLAGS to "-std=c89 -g -Wall -pedantic -Wno-missing-braces". We keep the
# -std=c89 dialect (lacc is written in C89 and self-hosts under it) and add our flags. -w silences the
# project's own clean-build warnings (they don't affect codegen) so a -Werror-free build stays quiet.
BASE_CFLAGS="-std=c89 -w"

# Host machine triple — bakes lacc's runtime INCLUDE_PATHS (where it resolves #include <...>). configure
# derives it from `$CC -dumpmachine`, but clang reports x86_64-pc-linux-gnu while Debian's multiarch libc
# headers live under /usr/include/x86_64-linux-gnu (gcc's triple). Without this, lacc can't find
# bits/libc-header-start.h and every libc-using source fails to preprocess. Pin to gcc's canonical Debian
# triple so the baked /usr/include/<host> path matches the actual headers (independent of the build CC).
HOST="$(gcc -dumpmachine 2>/dev/null || cc -dumpmachine)"

# ---------------------------------------------------------------------------
# (1) TEST build — lacc's OWN flags, no sanitizer. Installed under build-tests/install so test.sh's
#     check.sh can run lacc with its builtin headers available. Built first, then the tree is cleaned
#     for the sanitized build (the Makefile is in-tree, so the two builds can't coexist in one objdir).
# ---------------------------------------------------------------------------
TEST_PREFIX="$SRC/build-tests/install"
make distclean >/dev/null 2>&1 || true
./configure CC="$CC" CFLAGS="$BASE_CFLAGS -O2 $DEBUG_FLAGS" --prefix="$TEST_PREFIX" --host="$HOST"
make -j"$MAYHEM_JOBS" bin/lacc
make install
# Keep a copy of the normal-flags driver where test.sh looks for it.
mkdir -p "$SRC/build-tests"
cp -f bin/lacc "$SRC/build-tests/lacc"
echo "build.sh: test-oracle lacc -> $SRC/build-tests/lacc (prefix $TEST_PREFIX)"

# ---------------------------------------------------------------------------
# (2) FUZZ build — the COMPILER itself compiled WITH $SANITIZER_FLAGS so the fuzzed code is instrumented
#     (ASan+UBSan, halting, by default). The file-input Mayhem target lands at /mayhem/lacc, installed
#     under /mayhem/install so its builtin headers resolve when fuzzing real C sources.
# ---------------------------------------------------------------------------
# Relax THREE benign UBSan checks that lacc trips on essentially EVERY input — they'd abort the fuzzer
# before it explores any real defect (PORTING.md "benign UB that floods under halting UBSan"):
#   * nonnull-attribute     — hash.c clears an empty table with memset(NULL, 0, 0); UBSan flags the NULL
#                             arg to memset regardless of the zero length (well-defined in practice).
#   * shift / signed-integer-overflow — djb2_hash (strtab.c) does `(hash<<5)+hash` on a signed int that
#                             intentionally overflows for every string lacc interns (i.e. every source).
# Applied ONLY when UBSan is active (skip when SANITIZER_FLAGS is empty — the no-sanitizer off-switch
# stays a clean build). ASan and the REST of UBSan remain ON and HALTING, so real memory/UB defects in
# lacc's parser/codegen still crash the fuzzer. Smoke-tested: every valid seed runs to exit 0.
UBSAN_RELAX=""
if printf '%s' "$SANITIZER_FLAGS" | grep -q undefined; then
  UBSAN_RELAX="-fno-sanitize=nonnull-attribute,shift,signed-integer-overflow"
fi

FUZZ_PREFIX="/mayhem/install"
make distclean >/dev/null 2>&1 || true
./configure CC="$CC" CFLAGS="$BASE_CFLAGS $SANITIZER_FLAGS $UBSAN_RELAX $DEBUG_FLAGS" --prefix="$FUZZ_PREFIX" --host="$HOST"
make -j"$MAYHEM_JOBS" bin/lacc
make install
# $SRC is /mayhem and the build is in-tree at bin/lacc; place the fuzz target at /mayhem/lacc.
cp -f bin/lacc /mayhem/lacc

echo "build.sh: built /mayhem/lacc (sanitized fuzz target) and $SRC/build-tests/lacc (test oracle)"
ls -l /mayhem/lacc "$SRC/build-tests/lacc"
