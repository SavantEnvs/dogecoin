#!/usr/bin/env bash
# Builds (1) the sanitized fuzz harness against sanitized dogecoin libs (mayhem/build-fuzz) and
# (2) the project's own Boost test suite with normal flags (mayhem/build-test) for mayhem/test.sh.
# Everything comes from apt -dev packages + the in-tree leveldb/secp256k1/univalue, so a re-run is
# offline and idempotent. Both build dirs are gitignored via mayhem/.gitignore.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

COMMON_CONFIG=(--disable-wallet --without-gui --disable-bench --enable-tests --disable-hardening
  --without-miniupnpc --disable-ccache --disable-zmq --without-utils --without-daemon --without-libs)

# autogen output (configure, Makefile.in, ...) is gitignored upstream, so regenerate it here.
[ -x configure ] || ./autogen.sh

# configure_in <dir> <stamp> [VAR=value ...]: (re)configure out-of-tree only when the flags changed.
configure_in() {
  local dir="$1" stamp="$2"; shift 2
  mkdir -p "$dir"
  if [ ! -f "$dir/Makefile" ] || [ "$(cat "$dir/.flags" 2>/dev/null)" != "$stamp" ]; then
    (cd "$dir" && "$SRC/configure" "$@" "${COMMON_CONFIG[@]}")
    printf '%s' "$stamp" > "$dir/.flags"
  fi
}

# 1) sanitized libs + harness
FUZZ="$SRC/mayhem/build-fuzz"
FUZZ_COV="-fsanitize=fuzzer-no-link"   # SanCov on the fuzzed code; $LIB_FUZZING_ENGINE only covers its own link
SAN_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_COV"
configure_in "$FUZZ" "$SAN_CFLAGS" --disable-shared CFLAGS="$SAN_CFLAGS" CXXFLAGS="$SAN_CFLAGS"
make -C "$FUZZ/src" -j"$MAYHEM_JOBS" libdogecoin_server.a libdogecoin_common.a libdogecoin_util.a \
  libdogecoin_consensus.a crypto/libdogecoin_crypto.a univalue/libunivalue.la secp256k1/libsecp256k1.la

CXXFLAGS_H=(-std=c++11 -DHAVE_CONFIG_H -pthread -I"$FUZZ/src" -I"$FUZZ/src/config" -I"$SRC/src"
  -I"$SRC/src/leveldb/include" -I"$SRC/src/secp256k1/include" -I"$SRC/src/univalue/include")
LIBS=("$FUZZ/src/libdogecoin_server.a" "$FUZZ/src/libdogecoin_common.a" "$FUZZ/src/libdogecoin_util.a"
  "$FUZZ/src/libdogecoin_consensus.a" "$FUZZ/src/crypto/libdogecoin_crypto.a"
  "$FUZZ/src/univalue/.libs/libunivalue.a" "$FUZZ/src/secp256k1/.libs/libsecp256k1.a"
  -lboost_filesystem -lboost_program_options -lboost_thread -lboost_chrono -lboost_system -lcrypto -levent)

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$FUZZ/lsan_off.o"
$CC  $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$FUZZ/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_COV "${CXXFLAGS_H[@]}" -c "$SRC/mayhem/fuzz_dogecoin.cpp" -o "$FUZZ/fuzz_dogecoin.o"

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FUZZ/fuzz_dogecoin.o" "$FUZZ/lsan_off.o" \
  "${LIBS[@]}" -o /mayhem/fuzz_dogecoin
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$FUZZ/fuzz_dogecoin.o" "$FUZZ/standalone_main.o" "$FUZZ/lsan_off.o" \
  "${LIBS[@]}" -o /mayhem/fuzz_dogecoin-standalone

# 2) the project's own test suite with its normal flags
TESTD="$SRC/mayhem/build-test"
configure_in "$TESTD" "normal:$COVERAGE_FLAGS" CFLAGS="$COVERAGE_FLAGS" CXXFLAGS="$COVERAGE_FLAGS"
make -C "$TESTD/src" -j"$MAYHEM_JOBS" test/test_dogecoin
