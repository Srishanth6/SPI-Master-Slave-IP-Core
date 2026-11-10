#!/bin/bash
# Build with a deliberately injected RTL bug. The run must fail.
set -e
cd "$(dirname "$0")/.."
mkdir -p build logs results
fail=0

run_bug() {
  def=$1
  tag=$2
  scripts/vbuild.sh tb_spi_edge build/neg_$def +define+$def >/dev/null 2>&1 || {
    echo "build failed $def"; fail=1; return
  }
  set +e
  build/neg_$def/sim > results/neg_$def.log 2>&1
  rc=$?
  set -e
  echo "=== $def: exit code $rc"
  grep -m3 -iE "assertion failed|Error:|FAIL" results/neg_$def.log || true
  if [ $rc -eq 0 ] && ! grep -q "RESULT: FAILED" results/neg_$def.log; then
    echo "NEG $def: NOT CAUGHT (bad)"; fail=1
  else
    echo "NEG $def: caught ($tag) (expected)"
  fi
}

run_bug INJECT_BUG_SAMPLE "wrong sample edge"
run_bug INJECT_BUG_DONE "done not a pulse"
exit $fail
