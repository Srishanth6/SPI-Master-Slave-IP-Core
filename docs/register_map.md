# APB register map (`spi_apb`)

The wrapper is an AMBA 3 APB slave. `PREADY` is always 1 (no wait states) and
`PSLVERR` is always 0. Addresses are word-aligned.

| Offset | Name   | Access | Description |
|--------|--------|--------|-------------|
| 0x00   | CTRL   | RW     | See bits below. Writing 1 to bit 8 (`abort`) is a one-shot command. |
| 0x04   | CLKDIV | RW     | `[15:0]` clocks per SCLK half-period. Reset value 8, so SCLK = PCLK/16. A write of 0 is treated as 1 in the master. |
| 0x08   | TXDATA | RW     | Word to send, right-justified. A write starts a transfer if `enable=1` and `tx_ready=1`. |
| 0x0C   | RXDATA | RO     | Last received word, right-justified. A read clears `STATUS.rx_ready`. |
| 0x10   | STATUS | RO/W1C | See bits below. |

## CTRL bits

| Bit   | Name      | Reset | Meaning |
|-------|-----------|-------|---------|
| 0     | enable    | 0     | 1 = master is allowed to run |
| 1     | cpol      | 0     | Idle level of SCLK |
| 2     | cpha      | 0     | 0 = sample on the leading edge, 1 = sample on the trailing edge |
| 3     | lsb_first | 0     | 0 = MSB first, 1 = LSB first |
| 4     | irq_en    | 0     | Interrupt enable |
| 6:5   | width     | 00    | 00 = 8-bit, 01 = 16-bit, 10 = 32-bit. 11 is rejected (`cmd_err`) and the old width is kept. |
| 7     | cs_keep   | 0     | 1 = leave CS low after a word so the next word can follow |
| 8     | abort     | WO    | Write 1 to raise CS at once if a word is in progress |

`irq = irq_en & (done | cmd_err | aborted | overrun)`.

## STATUS bits

| Bit | Name     | Type | Meaning |
|-----|----------|------|---------|
| 0   | busy     | RO   | Master is not idle (CS may still be low in the trail half) |
| 1   | done     | W1C  | A word has finished. Write 1 to clear. |
| 2   | rx_ready | W1C  | `RXDATA` holds a new word. Cleared by a read of `RXDATA` or a write of 1 to this bit. |
| 3   | tx_ready | RO   | A `TXDATA` write will be accepted |
| 4   | overrun  | W1C  | A new word arrived before `RXDATA` was read |
| 5   | aborted  | W1C  | The last transfer was aborted mid-word |
| 6   | cmd_err  | W1C  | `TXDATA` was written while not ready, or CTRL had a bad width |

Reset value of STATUS is 0 (the master is disabled, so `tx_ready` is 0). After
`CTRL.enable` is set, `tx_ready` goes to 1.

## Software sequence

Example: mode 0, 8-bit, send 0xA5, read the slave reply.

```
CTRL   = 0x11        // enable + irq_en, mode 0, 8-bit
CLKDIV = 8
TXDATA = 0xA5        // starts the transfer
poll STATUS.done
value  = RXDATA      // also clears rx_ready
STATUS = 0x02        // clear done
```

For two words with CS held low, set `CTRL.cs_keep` first, write `TXDATA` twice
(wait for `tx_ready` or `done` each time), then clear `cs_keep` and wait until
`busy` is 0 so CS goes high.
