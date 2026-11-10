#!/bin/bash
# Linux/macOS: Icarus directed tests, Verilator edge/random if present.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build waves results
SEEDS="${SEEDS:-1 42 2026}"

echo "=== tb_spi_core (Icarus) ==="
iverilog -g2012 -o build/tb_spi_core rtl/*.v tb/spi_monitor.v tb/tb_spi_core.v
vvp -n build/tb_spi_core 2>&1 | tee results/tb_spi_core.log

echo "=== tb_spi_apb (Icarus) ==="
iverilog -g2012 -o build/tb_spi_apb rtl/*.v tb/spi_monitor.v tb/tb_spi_apb.v
vvp -n build/tb_spi_apb 2>&1 | tee results/tb_spi_apb.log

if command -v verilator >/dev/null 2>&1; then
  echo "=== tb_spi_edge (Verilator + SVA) ==="
  scripts/vbuild.sh tb_spi_edge build/edge --trace
  build/edge/sim 2>&1 | tee results/tb_spi_edge.log

  echo "=== tb_spi_rand (Verilator + SVA) ==="
  scripts/vbuild.sh tb_spi_rand build/rand
  for s in $SEEDS; do
    build/rand/sim +SEED=$s 2>&1 | tee results/tb_spi_rand_seed$s.log
  done
else
  echo "Verilator not found; skipped edge and random tests."
fi

if grep -q "RESULT: FAILED" results/tb_spi_core.log results/tb_spi_apb.log results/tb_spi_edge.log results/tb_spi_rand_seed*.log 2>/dev/null; then
  echo "One or more tests failed."; exit 1
fi
echo "All completed test logs report PASS."
