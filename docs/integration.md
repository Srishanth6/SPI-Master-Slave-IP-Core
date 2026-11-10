# Integration guide

## Master only

Instantiate `rtl/spi_master.v`. Drive `enable`, `clkdiv`, `cpol`, `cpha`,
`lsb_first`, `nbits`, `start`, `cs_keep`, `abort_req` and `tx_data`. Sample
`rx_data` when `done` pulses. Connect `sclk`, `mosi`, `cs_n` and `miso` to
pads or to a slave.

`clkdiv` is the number of system clocks in one SCLK half-period, so

    f_SCLK = f_clk / (2 * clkdiv)

with `clkdiv >= 1`. A value of 0 is treated as 1.

`nbits` may be any value from 1 to `MAX_WIDTH` (default 32). Data is
right-justified in the 32-bit buses.

## Slave only

Instantiate `rtl/spi_slave.v`. Set `cpol`, `cpha`, `lsb_first` and `nbits` to
match the master. `tx_data` is the word that will be shifted out. It is
sampled when CS falls, and again between words if CS stays low, so you can
update it after `rx_valid`.

`ASYNC` selects how SCLK, CS and MOSI enter the system clock domain:

- `ASYNC=0` — one flip-flop, for a master on the same clock. This is what
  `spi_loopback` uses. The SCLK half-period should be at least two system
  clocks (`clkdiv >= 2`) so the slave can present a bit before the master
  samples it.
- `ASYNC=1` — two flip-flops, for an external master. The SCLK half-period
  should also be at least two system clocks so that every edge is seen.

MISO is only driven while CS is low (`miso_oe`). Wire it as

    assign miso_pad = miso_oe ? miso : 1'bz;

and add a pull-up on the board or in the testbench.

If CS is tied high, the slave never selects and does not drive MISO. If CS is
tied low, words are framed by the bit count alone.

## APB wrapper

`rtl/spi_apb.v` wraps the master only. The slave, if you need one, is a
separate instance. See [register_map.md](register_map.md) for the software
view.

## FPGA example

`fpga/spi_icebreaker.v` plus `fpga/icebreaker.pcf` is a small on-chip
loopback for the iCEBreaker (iCE40UP5K, 12 MHz). After reset it sends four
8-bit words in mode 0. The green LED lights if they all match; the red LED
lights if one fails. The SPI pins are also on PMOD 1A so you can watch them
with a logic analyser.

Build:

    yosys -p "read_verilog fpga/spi_icebreaker.v rtl/*.v; synth_ice40 -top spi_icebreaker -json ice.json"
    nextpnr-ice40 --up5k --package sg48 --json ice.json --pcf fpga/icebreaker.pcf --asc ice.asc
    icepack ice.asc ice.bin
