# Limitations and known issues

- On-chip loopback (master and slave on the same clock, `ASYNC=0`) needs
  `clkdiv >= 2`. `clkdiv=1` does produce SCLK = clk/2, and that was checked,
  but the slave is one clock behind the registered SCLK and cannot meet the
  sample window. Treat `clkdiv=1` as unsupported for a same-clock slave.
- With `ASYNC=1` the slave also needs an SCLK half-period of at least two
  system clocks, so that each edge survives the synchroniser.
- There is one chip-select, no FIFO and no DMA. Software (or the APB
  sequence) writes one word at a time. A write while the master is not ready
  is rejected (`cmd_err`).
- Changing CPOL or CPHA in the middle of a word is not supported. Change
  them while the core is idle.
- There is no glitch filter on SCLK or CS.
- Rise and fall times, and pad delay, are not modelled. Timing is checked
  at the digital edges.
- Formal proofs are bounded model checks of the master, depth 60, with
  `clkdiv=2`, 8-bit words, and stable CPOL/CPHA. This is not a complete
  unbounded proof, and the slave is not in the formal netlist.
- The iCEBreaker build is an on-chip loopback. It has not been run on a
  real board in this repository.
- Line and toggle coverage was collected with Verilator on the random
  testbench. Those numbers cover the paths that the random stimulus hit,
  not every branch of the RTL.
