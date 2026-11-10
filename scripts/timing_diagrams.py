#!/usr/bin/env python3
"""Ideal SPI timing diagrams for modes 0-3 (not from a VCD)."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pathlib import Path

BITS = "10100101"  # 0xA5, MSB first

def add_step(ax, t, v, y, **kw):
    xt, yt = [t[0]], [v[0] + y]
    for i in range(1, len(t)):
        xt += [t[i], t[i]]
        yt += [v[i-1] + y, v[i] + y]
    ax.plot(xt, yt, lw=1.6, **kw)

def draw_mode(path, cpol, cpha, title):
    # half-period units 0..20
    # CS falls at 1, rises at 19
    # 8 bits, two edges each
    t_cs = [0, 1, 19, 20]
    v_cs = [1, 0, 1, 1]
    # clock
    t_ck = [0, 1]
    v_ck = [cpol, cpol]
    # first leading at time 2, then every 1 unit, 16 edges, last trailing at 17
    level = cpol
    for e in range(16):
        t_ck.append(2 + e)
        level = 1 - level
        v_ck.append(level)
    t_ck += [18, 20]
    v_ck += [cpol, cpol]
    # MOSI: CPHA=0 valid from CS, changes on trailing (odd edges)
    # CPHA=1 changes on leading (even edges, starting at first leading)
    t_mo, v_mo = [0], [0]
    if cpha == 0:
        t_mo, v_mo = [0, 1], [0, int(BITS[0])]
        for i in range(1, 8):
            t_mo.append(2 + (2 * i - 1))  # trailing of previous
            v_mo.append(int(BITS[i]))
        t_mo += [19, 20]
        v_mo += [int(BITS[7]), 0]
    else:
        t_mo, v_mo = [0, 2], [0, int(BITS[0])]
        for i in range(1, 8):
            t_mo.append(2 + 2 * i)  # leading of this bit
            v_mo.append(int(BITS[i]))
        t_mo += [19, 20]
        v_mo += [int(BITS[7]), 0]

    fig, ax = plt.subplots(figsize=(9.5, 3.4))
    add_step(ax, t_cs, v_cs, 6, color="C0")
    add_step(ax, t_ck, v_ck, 3, color="C1")
    add_step(ax, t_mo, v_mo, 0, color="C2")
    # sample arrows on sample edges
    for e in range(8):
        if cpha == 0:
            te = 2 + 2 * e          # leading
        else:
            te = 2 + 2 * e + 1      # trailing
        ax.annotate("", xy=(te, 0.15), xytext=(te, 1.15),
                    arrowprops=dict(arrowstyle="->", color="0.3", lw=0.9))
    ax.set_yticks([0, 1, 3, 4, 6, 7])
    ax.set_yticklabels(["0", "MOSI  1", "0", "SCLK  1", "0", "CS    1"])
    ax.set_xlim(0, 20)
    ax.set_ylim(-0.4, 7.6)
    ax.set_xlabel("time (half-periods of SCLK)")
    ax.set_title(title)
    ax.grid(True, axis="x", alpha=0.25)
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)
    print("wrote", path)

def main():
    out = Path("docs/figs")
    out.mkdir(parents=True, exist_ok=True)
    draw_mode(out / "timing_mode0.png", 0, 0, "SPI mode 0 (CPOL=0, CPHA=0), MOSI = 0xA5, arrows mark sample edges")
    draw_mode(out / "timing_mode1.png", 0, 1, "SPI mode 1 (CPOL=0, CPHA=1), MOSI = 0xA5, arrows mark sample edges")
    draw_mode(out / "timing_mode2.png", 1, 0, "SPI mode 2 (CPOL=1, CPHA=0), MOSI = 0xA5, arrows mark sample edges")
    draw_mode(out / "timing_mode3.png", 1, 1, "SPI mode 3 (CPOL=1, CPHA=1), MOSI = 0xA5, arrows mark sample edges")

if __name__ == "__main__":
    main()
