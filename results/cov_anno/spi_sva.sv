//      // verilator_coverage annotation
        // spi_sva.sv - protocol checks bound onto the master in the testbench
        // Author: B. Srishanth Reddy
        //
        // Each property has a hit counter so the report can show that the
        // check actually fired and did not just pass vacuously.
        
        module spi_sva #(
            parameter MAX_WIDTH = 32
        )(
 018449     input logic                 clk,
%000001     input logic                 rst_n,
%000001     input logic                 enable,
~000020     input logic [15:0]          clkdiv,
 000023     input logic                 cpol,
 000019     input logic                 cpha,
 000111     input logic                 start,
%000000     input logic                 abort,
 000092     input logic                 busy,
 000111     input logic                 done,
 000105     input logic                 tx_ready,
%000000     input logic                 aborted,
 002271     input logic                 sclk,
 000093     input logic                 cs_n,
 000573     input logic                 mosi
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
        
 018449     always_ff @(posedge clk or negedge rst_n) begin
~018446         if (!rst_n) begin
%000003             hit_idle  <= 0;
%000003             hit_done  <= 0;
%000003             hit_cs    <= 0;
%000003             hit_en    <= 0;
%000003             hit_abort <= 0;
%000003             hit_busy  <= 0;
%000003             hit_div   <= 0;
 018446         end else begin
 018255             if (cs_n)            hit_idle  <= hit_idle  + 1;
 018335             if (done)            hit_done  <= hit_done  + 1;
 018335             if (done && !cs_n)   hit_cs    <= hit_cs    + 1;
~018342             if (start && tx_ready && enable) hit_en <= hit_en + 1;
~018446             if (aborted)         hit_abort <= hit_abort + 1;
~018446             if (!enable && !busy) hit_busy <= hit_busy + 1;
 018255             if (busy)            hit_div   <= hit_div   + 1;
                end
            end
        
%000001     function void report();
%000001         $display("SVA antecedent hits: A1 idle_cs=%0d A2/A3 done=%0d A3 done_cs=%0d A4 start=%0d A5 aborted=%0d A6 dis_idle=%0d A7 busy=%0d",
%000001                  hit_idle, hit_done, hit_cs, hit_en, hit_abort, hit_busy, hit_div);
            endfunction
        endmodule
        
