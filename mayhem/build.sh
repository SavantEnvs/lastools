#!/usr/bin/env bash
#
# mayhem/build.sh — builds LASlib/LASzip twice (sanitized + instrumented for the fuzz harnesses, and a
# plain build for the functional oracle), the fuzz harnesses and their -standalone reproducers, and
# the CLI tools mayhem/test.sh drives. Nothing is fetched: LAStools has no external build dependency.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-/mayhem}"
cd "$SRC"

# 1) Sanitized + SanCov-instrumented library for the fuzz harnesses. SanCov (fuzzer-no-link) is added
#    unconditionally so the library has coverage even when SANITIZER_FLAGS is empty. NDEBUG= keeps the
#    library's assert()s live (a failed one is a finding).
# alignment: the LASzip decoders load U64 from unaligned buffers (benign on x86, fires on every LAZ).
# sized-deallocation: LASintervalCell nodes are deleted through a base pointer without a virtual
# destructor, which ASan's new-delete-type-mismatch reports on every LAX index.
FUZZ_FLAGS="-O2 $SANITIZER_FLAGS -fno-sanitize=alignment -fno-sized-deallocation -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
make -f mayhem/lib.mk -j"$MAYHEM_JOBS" BUILD=mayhem/build-fuzz NDEBUG= CC="$CC" CXX="$CXX" CXXFLAGS="$FUZZ_FLAGS" lib

# 2) Harnesses: libFuzzer binary + a run-once -standalone reproducer, both with leak detection off.
OBJ=mayhem/build-fuzz/harness
mkdir -p "$OBJ"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$OBJ/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"
INC="-ILASzip/include/laszip -ILASzip/src -ILASlib/inc"
for h in fuzz_lasreader fuzz_lasindex fuzz_lasreadopener; do
  $CXX -std=c++17 -DUNORDERED -DHAVE_UNORDERED_MAP $FUZZ_FLAGS $INC -c "mayhem/$h.cpp" -o "$OBJ/$h.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OBJ/$h.o" "$OBJ/lsan_off.o" \
      mayhem/build-fuzz/liblaslib.a -o "/mayhem/$h"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$OBJ/$h.o" "$OBJ/lsan_off.o" "$OBJ/standalone_main.o" \
      mayhem/build-fuzz/liblaslib.a -o "/mayhem/$h-standalone"
done

# 3) The tools mayhem/test.sh drives, with the project's NORMAL flags (no sanitizer, no -gdwarf-3).
make -f mayhem/lib.mk -j"$MAYHEM_JOBS" BUILD=mayhem/build-tests CC="$CC" CXX="$CXX" \
    CXXFLAGS="-O2 $COVERAGE_FLAGS" tools
