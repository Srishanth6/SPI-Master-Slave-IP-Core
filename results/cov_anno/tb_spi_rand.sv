//      // verilator_coverage annotation
        // tb_spi_rand.sv - constrained-random loopback with a scoreboard
        // Author: B. Srishanth Reddy
        `timescale 1ns/1ps
        module tb_spi_rand;
            localparam W = 32;
        
~018449     logic clk = 0, rst_n = 0;
 036897     always #10 clk = ~clk;
        
%000001     logic             enable = 1;
~000020     logic [15:0]      clkdiv = 16'd2;
~000023     logic             cpol = 0, cpha = 0, lsb_first = 0;
~000022     logic [5:0]       nbits = 6'd8;
~000111     logic             start = 0, cs_keep = 0, abort = 0;
~000034     logic [W-1:0]     m_tx = 0, s_tx = 0;
 000034     wire  [W-1:0]     m_rx, s_rx;
~000111     wire              busy, done, tx_ready, aborted;
~000111     wire              s_rx_valid, s_selected, s_overrun, s_mid_cs_abort;
~000111     logic             s_rx_clear = 0;
 002271     wire              sclk, mosi, miso, cs_n;
        
            spi_loopback #(.MAX_WIDTH(W)) dut (
                .clk, .rst_n, .enable, .clkdiv, .cpol, .cpha, .lsb_first, .nbits,
                .start, .cs_keep, .abort_req(abort), .m_tx, .m_rx, .s_tx, .s_rx,
                .busy, .done, .tx_ready, .aborted,
                .s_rx_valid, .s_selected, .s_overrun, .s_mid_cs_abort, .s_rx_clear,
                .sclk, .mosi, .miso, .cs_n
            );
        
            spi_sva #(.MAX_WIDTH(W)) sva (
                .clk, .rst_n, .enable, .clkdiv, .cpol, .cpha,
                .start, .abort, .busy, .done, .tx_ready, .aborted,
                .sclk, .cs_n, .mosi
            );
        
            int unsigned seed;
            int errors, checks, n_xfer;
            int cov_mode[4];
            int cov_lsb, cov_msb, cov_w8, cov_w16, cov_w32, cov_keep, cov_div[4];
        
%000001     initial begin
%000001         seed = 1;
%000001         if ($value$plusargs("SEED=%d", seed)) ;
%000001         $display("tb_spi_rand SEED=%0d", seed);
            end
        
 000888     function automatic logic [31:0] mask(input logic [31:0] d, input int bits);
~000520         if (bits >= 32) return d;
 000888         return d & ((32'h1 << bits) - 1);
            endfunction
        
 000111     task automatic one_xfer(input logic [31:0] mtx, input logic [31:0] stx);
 000111         logic [31:0] got_s;
 000111         bit saw;
 000111         s_tx = stx;
 000111         m_tx = mtx;
 000111         saw = 0;
 000111         got_s = 0;
 000111         @(posedge clk); start = 1;
 000111         @(posedge clk); start = 0;
 017825         while (!done) begin
 017825             @(posedge clk);
 017714             if (s_rx_valid) begin
 000111                 saw = 1;
 000111                 got_s = s_rx;
 000111                 s_rx_clear = 1;
                    end else
 017714                 s_rx_clear = 0;
                end
 000111         @(posedge clk);
 000111         s_rx_clear = 0;
 000084         if (!cs_keep)
 000270             while (busy) @(posedge clk);
 000111         checks += 2;
~000111         if (!saw || mask(got_s, nbits) !== mask(mtx, nbits)) begin
%000000             errors++;
%000000             $display("  [FAIL] slave rx=%h expected=%h (mode=%0d%0d nbits=%0d lsb=%0d div=%0d)",
%000000                      got_s, mask(mtx, nbits), cpol, cpha, nbits, lsb_first, clkdiv);
                end
~000111         if (mask(m_rx, nbits) !== mask(stx, nbits)) begin
%000000             errors++;
%000000             $display("  [FAIL] master rx=%h expected=%h (mode=%0d%0d nbits=%0d lsb=%0d div=%0d)",
%000000                      m_rx, mask(stx, nbits), cpol, cpha, nbits, lsb_first, clkdiv);
                end
 000111         n_xfer++;
 000111         cov_mode[{cpol, cpha}]++;
 000064         if (lsb_first) cov_lsb++; else cov_msb++;
 000046         if (nbits==8) cov_w8++; else if (nbits==16) cov_w16++; else cov_w32++;
 000084         if (cs_keep) cov_keep++;
 000068         if (clkdiv<=2) cov_div[0]++; else if (clkdiv<=8) cov_div[1]++;
%000000         else if (clkdiv<=32) cov_div[2]++; else cov_div[3]++;
            endtask
        
            int i, k, bits_sel, div_sel, burst;
 000034     logic [31:0] a, b;
        
%000001     initial begin
%000001         errors = 0; checks = 0; n_xfer = 0;
%000001         cov_lsb=0; cov_msb=0; cov_w8=0; cov_w16=0; cov_w32=0; cov_keep=0;
%000004         foreach (cov_mode[i]) cov_mode[i]=0;
%000004         foreach (cov_div[i]) cov_div[i]=0;
        
%000004         repeat (4) @(posedge clk);
%000001         rst_n = 1;
%000001         enable = 1;
%000001         @(posedge clk);
        
                // Directed warm-up: one transfer in each mode
%000001         nbits = 8; clkdiv = 2; lsb_first = 0; cs_keep = 0;
%000004         for (i = 0; i < 4; i++) begin
%000004             cpol = i[1]; cpha = i[0];
%000004             one_xfer(32'hA5, 32'h5A);
                end
        
                // Constrained-random group
~000080         for (k = 0; k < 80; k++) begin
 000080             i = $urandom(seed);
 000080             seed = seed + 1;
 000080             cpol = i[0];
 000080             cpha = i[1];
 000080             lsb_first = i[2];
 000080             bits_sel = i[4:3];
 000080             nbits = (bits_sel==0) ? 8 : (bits_sel==1) ? 16 : 32;
 000080             div_sel = i[6:5];
 000080             clkdiv = (div_sel==0) ? 16'd2 : (div_sel==1) ? 16'd3 : (div_sel==2) ? 16'd5 : 16'd8;
 000080             cs_keep = 0;
 000080             a = $urandom(seed); seed++;
 000080             b = $urandom(seed); seed++;
 000080             one_xfer(a, b);
                end
        
                // Random back-to-back bursts with CS held
%000008         for (k = 0; k < 8; k++) begin
%000008             i = $urandom(seed); seed++;
%000008             cpol = i[0]; cpha = i[1]; lsb_first = i[2];
%000008             nbits = i[3] ? 16 : 8;
%000008             clkdiv = i[4] ? 16'd3 : 16'd2;
%000008             cs_keep = 1;
%000008             burst = 2 + (i[6:5]); // 2..5 words
~000027             for (i = 0; i < burst; i++) begin
 000027                 a = $urandom(seed); seed++;
 000027                 b = $urandom(seed); seed++;
 000027                 one_xfer(a, b);
                    end
%000008             cs_keep = 0;
%000008             @(posedge clk);
%000003             while (busy) @(posedge clk);
                end
        
%000001         $display("--------------------------------------------------");
%000001         $display("Transfers: %0d   checks: %0d   errors: %0d", n_xfer, checks, errors);
%000001         $display("Coverage counts:");
%000001         $display("  mode 0/1/2/3 = %0d/%0d/%0d/%0d", cov_mode[0], cov_mode[1], cov_mode[2], cov_mode[3]);
%000001         $display("  msb/lsb = %0d/%0d", cov_msb, cov_lsb);
%000001         $display("  width 8/16/32 = %0d/%0d/%0d", cov_w8, cov_w16, cov_w32);
%000001         $display("  cs_keep words = %0d", cov_keep);
%000001         $display("  clkdiv 2 / 3-8 / 5 / 8+ bins = %0d/%0d/%0d/%0d",
%000001                  cov_div[0], cov_div[1], cov_div[2], cov_div[3]);
%000001         sva.report();
%000001         if (errors == 0) $display("RESULT: ALL TESTS PASSED");
%000000         else             $display("RESULT: FAILED");
%000001         #100 $finish;
            end
        
%000000     initial begin
%000000         #200_000_000;
%000000         $display("TIMEOUT");
%000000         $finish;
            end
        endmodule
        
