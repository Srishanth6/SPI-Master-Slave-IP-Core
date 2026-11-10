#!/usr/bin/env python3
"""Render SPI mode waveforms from waves/tb_spi_waves.vcd (matplotlib, not GTKWave)."""
from pathlib import Path
import sys

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:
    print("matplotlib is not installed; skipped waveform images")
    sys.exit(0)

def parse_vcd(path):
    ids = {}
    names = {}
    changes = []  # (time, id, value)
    time = 0
    with open(path) as f:
        in_defs = True
        for line in f:
            line = line.strip()
            if not line:
                continue
            if in_defs:
                if line.startswith("$var"):
                    parts = line.split()
                    # $var wire 1 <id> <name>
                    if len(parts) >= 5:
                        ids[parts[3]] = parts[4]
                        names[parts[4]] = parts[3]
                if line.startswith("$dumpvars") or line == "$enddefinitions $end":
                    in_defs = False
                continue
            if line.startswith("#"):
                time = int(line[1:])
                continue
            if line.startswith("$"):
                continue
            if line[0] in "01xzXZ":
                changes.append((time, line[1:], line[0].lower()))
            elif line[0] in "bB":
                val, ident = line[1:].split()
                changes.append((time, ident, val.lower()))
    return ids, changes

def series(ids, changes, name, t0, t1):
    ident = None
    for i, n in ids.items():
        if n == name:
            ident = i
            break
    if ident is None:
        return [], []
    ts, vs, cur = [], [], 0
    # rebuild from start
    val = 0
    last_t = None
    for t, i, v in changes:
        if i != ident:
            continue
        try:
            val = int(v, 2) if v not in ("x", "z") else 0
        except ValueError:
            val = 0
        if t0 <= t <= t1:
            ts.append(t)
            vs.append(val)
        last_t = t
    return ts, vs

def step_plot(ax, ts, vs, label, yoff):
    if not ts:
        return
    # convert to ns if the vcd is in ps (timescale 1ns/1ps in this project: integers are ps? 
    # Icarus with 1ns/1ps often dumps in ps)
    tns = [t / 1000.0 for t in ts]
    vals = [v + yoff for v in vs]
    # hold last sample to the next
    xt, yt = [tns[0]], [vals[0]]
    for i in range(1, len(tns)):
        xt.append(tns[i]); yt.append(vals[i-1])
        xt.append(tns[i]); yt.append(vals[i])
    ax.plot(xt, yt, lw=1.4, label=label)

def main():
    vcd = Path("waves/tb_spi_waves.vcd")
    if not vcd.exists():
        print("missing", vcd)
        sys.exit(1)
    ids, changes = parse_vcd(vcd)
    times = [t for t, _, _ in changes]
    if not times:
        print("empty vcd")
        sys.exit(1)
    tmax = max(times)
    # four equal windows after a short reset
    # better: split by CS high-to-low events
    cs_id = None
    for i, n in ids.items():
        if n == "cs_n":
            cs_id = i
    falls = []
    last = 1
    for t, i, v in changes:
        if i != cs_id:
            continue
        try:
            val = int(v, 2)
        except ValueError:
            continue
        if last == 1 and val == 0:
            falls.append(t)
        last = val
    if len(falls) < 4:
        # fallback equal splits
        span = tmax // 4
        windows = [(i * span, (i + 1) * span) for i in range(4)]
    else:
        windows = []
        for i, t0 in enumerate(falls[:4]):
            t1 = falls[i + 1] if i + 1 < len(falls) else tmax
            pad = (t1 - t0) // 8 + 20000
            windows.append((max(0, t0 - pad), t1))

    outdir = Path("docs/figs")
    outdir.mkdir(parents=True, exist_ok=True)
    modes = ["Mode 0 (CPOL=0, CPHA=0)", "Mode 1 (CPOL=0, CPHA=1)",
             "Mode 2 (CPOL=1, CPHA=0)", "Mode 3 (CPOL=1, CPHA=1)"]
    for i, ((t0, t1), title) in enumerate(zip(windows, modes)):
        fig, ax = plt.subplots(figsize=(9.5, 3.6))
        for name, off in (("cs_n", 6), ("sclk", 4), ("mosi", 2), ("miso", 0)):
            ts, vs = series(ids, changes, name, t0, t1)
            step_plot(ax, ts, vs, name, off)
        ax.set_yticks([0, 1, 2, 3, 4, 5, 6, 7])
        ax.set_yticklabels(["0", "1  miso", "0", "1  mosi", "0", "1  sclk", "0", "1  cs_n"])
        ax.set_xlabel("time (ns)")
        ax.set_title(title + "  —  rendered from waves/tb_spi_waves.vcd")
        ax.set_ylim(-0.3, 7.5)
        ax.grid(True, axis="x", alpha=0.25)
        fig.tight_layout()
        fn = outdir / f"wave_mode{i}.png"
        fig.savefig(fn, dpi=120)
        plt.close(fig)
        print("wrote", fn)

if __name__ == "__main__":
    main()
