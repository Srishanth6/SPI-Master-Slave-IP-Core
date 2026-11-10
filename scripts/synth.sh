#!/bin/bash
# Yosys generic + ice40 mapping, and nextpnr for the iCEBreaker top.
set -e
cd "$(dirname "$0")/.."
mkdir -p results/synth
HAVE_PNR=0
command -v nextpnr-ice40 >/dev/null 2>&1 && HAVE_PNR=1

run() {
  name=$1
  src=$2
  yosys -q -l results/synth/${name}_generic.log -p \
    "read_verilog $src; synth -top $name -flatten; abc -g cmos2; opt_clean; tee -o results/synth/${name}_generic.stat stat"
  yosys -q -l results/synth/${name}_ice40.log -p \
    "read_verilog $src; synth_ice40 -top $name; tee -o results/synth/${name}_ice40.stat stat; write_json results/synth/${name}_ice40.json"
}

run spi_master     "rtl/spi_master.v"
run spi_slave      "rtl/spi_slave.v"
run spi_apb        "rtl/spi_apb.v rtl/spi_master.v"
run spi_loopback   "rtl/*.v"
run spi_icebreaker "fpga/spi_icebreaker.v rtl/*.v"

if [ $HAVE_PNR = 1 ]; then
  nextpnr-ice40 --up5k --package sg48 --seed 1 \
    --json results/synth/spi_icebreaker_ice40.json \
    --pcf fpga/icebreaker.pcf \
    --log results/synth/spi_icebreaker_pnr.log
else
  echo "nextpnr-ice40 not found, skipped place-and-route"
fi

echo "Logs are in results/synth/. See results/synth_summary.txt if present."
