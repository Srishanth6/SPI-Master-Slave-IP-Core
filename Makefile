# SPI master/slave IP core
# Author: B. Srishanth Reddy
SEEDS  ?= 1 42 2026
PYTHON ?= python3
SHELL  := /bin/bash
.SHELLFLAGS := -o pipefail -c

.PHONY: all core apb edge rand lint synth formal waves neg coverage clean

all: core apb edge rand lint

core:
	mkdir -p build waves results
	iverilog -g2012 -o build/tb_spi_core rtl/*.v tb/spi_monitor.v tb/tb_spi_core.v
	vvp -n build/tb_spi_core 2>&1 | tee results/tb_spi_core.log

apb:
	mkdir -p build waves results
	iverilog -g2012 -o build/tb_spi_apb rtl/*.v tb/spi_monitor.v tb/tb_spi_apb.v
	vvp -n build/tb_spi_apb 2>&1 | tee results/tb_spi_apb.log

edge:
	mkdir -p build waves results
	scripts/vbuild.sh tb_spi_edge build/edge --trace
	build/edge/sim 2>&1 | tee results/tb_spi_edge.log

rand:
	mkdir -p build waves results
	scripts/vbuild.sh tb_spi_rand build/rand --coverage
	set -e; for s in $(SEEDS); do build/rand/sim +SEED=$$s 2>&1 | tee results/tb_spi_rand_seed$$s.log; done

lint:
	mkdir -p results
	verilator --lint-only -Wall --top-module spi_loopback rtl/*.v 2>&1 | tee results/lint_all.log

synth:
	scripts/synth.sh

formal:
	mkdir -p results
	sby -f formal/spi_master.sby -d build/formal_bmc 2>&1 | tee results/formal_bmc.log
	sby -f formal/spi_master_cover.sby -d build/formal_cover 2>&1 | tee results/formal_cover.log

waves:
	mkdir -p build waves docs/figs results
	iverilog -g2012 -o build/tb_spi_waves rtl/*.v tb/tb_spi_waves.v
	vvp -n build/tb_spi_waves
	$(PYTHON) scripts/render_waves.py
	$(PYTHON) scripts/timing_diagrams.py

neg:
	scripts/neg_tests.sh

coverage: rand
	mkdir -p results/cov_anno
	verilator_coverage coverage.dat --annotate results/cov_anno 2>&1 | tee results/coverage.txt

clean:
	rm -rf build waves/*.vcd coverage.dat
