#!/bin/bash
# usage: vbuild.sh <top> <outdir> [extra verilator args...]
set -e
top=$1; out=$2; shift 2
verilator --binary --timing --assert --timescale 1ns/1ps \
  -Wno-fatal -Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-TIMESCALEMOD \
  --top-module "$top" -Mdir "$out" "$@" rtl/*.v sva/spi_sva.sv tb/$top.sv -o sim
