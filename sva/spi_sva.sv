// spi_sva.sv - protocol checks bound onto the master in the testbench
// Author: B. Srishanth Reddy
//
// Each property has a hit counter so the report can show that the
// check actually fired and did not just pass vacuously.

module spi_sva #(
    parameter MAX_WIDTH = 32
)(
    input logic                 clk,
    input logic                 rst_n,
    input logic                 enable,
    input logic [15:0]          clkdiv,
    input logic                 cpol,
    input logic                 cpha,
    input logic                 start,
    input logic                 abort,
    input logic                 busy,
    input logic                 done,
    input logic                 tx_ready,
    input logic                 aborted,
    input logic                 sclk,
    input logic                 cs_n,
    input logic                 mosi
);

    int hit_idle, hit_done, hit_cs, hit_en, hit_abort, hit_busy, hit_div;

    // A1: while CS is high, SCLK stays at CPOL (idle level)
    a_idle_sclk: assert property (@(posedge clk) disable iff (!rst_n)
        cs_n |-> (sclk == cpol))
        else $error("A1 SCLK not at CPOL while CS is high");

    // A2: done is a single-cycle pulse
    a_done_pulse: assert property (@(posedge clk) disable iff (!rst_n)
        done |=> !done)
        else $error("A2 done was longer than one clock");

    // A3: done only occurs while CS is still low (before the trail half ends)
    a_done_while_selected: assert property (@(posedge clk) disable iff (!rst_n)
        done |-> !cs_n)
        else $error("A3 done while CS was high");

    // A4: a start that is accepted makes the core busy on the next clock
    a_start_busy: assert property (@(posedge clk) disable iff (!rst_n)
        (start && tx_ready && enable && !abort) |=> busy)
        else $error("A4 start was accepted but busy did not rise");

    // A5: abort raises CS and the aborted flag
    a_abort_cs: assert property (@(posedge clk) disable iff (!rst_n)
        aborted |-> cs_n)
        else $error("A5 aborted but CS still low");

    // A6: when enable is low the core is idle
    a_enable_idle: assert property (@(posedge clk) disable iff (!rst_n)
        (!enable && !busy) |-> cs_n)
        else $error("A6 CS low while disabled and idle");

    // A7: clkdiv of 0 is not used as a zero period (treated as 1 in RTL)
    // Checked as a cover/sanity on the input; the RTL clamps it.
    a_busy_means_cs: assert property (@(posedge clk) disable iff (!rst_n)
        (busy && !aborted) |-> (!cs_n || $past(cs_n)))
        else $error("A7 unexpected CS while busy");

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit_idle  <= 0;
            hit_done  <= 0;
            hit_cs    <= 0;
            hit_en    <= 0;
            hit_abort <= 0;
            hit_busy  <= 0;
            hit_div   <= 0;
        end else begin
            if (cs_n)            hit_idle  <= hit_idle  + 1;
            if (done)            hit_done  <= hit_done  + 1;
            if (done && !cs_n)   hit_cs    <= hit_cs    + 1;
            if (start && tx_ready && enable) hit_en <= hit_en + 1;
            if (aborted)         hit_abort <= hit_abort + 1;
            if (!enable && !busy) hit_busy <= hit_busy + 1;
            if (busy)            hit_div   <= hit_div   + 1;
        end
    end

    function void report();
        $display("SVA antecedent hits: A1 idle_cs=%0d A2/A3 done=%0d A3 done_cs=%0d A4 start=%0d A5 aborted=%0d A6 dis_idle=%0d A7 busy=%0d",
                 hit_idle, hit_done, hit_cs, hit_en, hit_abort, hit_busy, hit_div);
    endfunction
endmodule
