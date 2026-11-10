// tb_spi_rand.sv - constrained-random loopback with a scoreboard
// Author: B. Srishanth Reddy
`timescale 1ns/1ps
module tb_spi_rand;
    localparam W = 32;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    logic             enable = 1;
    logic [15:0]      clkdiv = 16'd2;
    logic             cpol = 0, cpha = 0, lsb_first = 0;
    logic [5:0]       nbits = 6'd8;
    logic             start = 0, cs_keep = 0, abort = 0;
    logic [W-1:0]     m_tx = 0, s_tx = 0;
    wire  [W-1:0]     m_rx, s_rx;
    wire              busy, done, tx_ready, aborted;
    wire              s_rx_valid, s_selected, s_overrun, s_mid_cs_abort;
    logic             s_rx_clear = 0;
    wire              sclk, mosi, miso, cs_n;

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

    initial begin
        seed = 1;
        if ($value$plusargs("SEED=%d", seed)) ;
        $display("tb_spi_rand SEED=%0d", seed);
    end

    function automatic logic [31:0] mask(input logic [31:0] d, input int bits);
        if (bits >= 32) return d;
        return d & ((32'h1 << bits) - 1);
    endfunction

    task automatic one_xfer(input logic [31:0] mtx, input logic [31:0] stx);
        logic [31:0] got_s;
        bit saw;
        s_tx = stx;
        m_tx = mtx;
        saw = 0;
        got_s = 0;
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        while (!done) begin
            @(posedge clk);
            if (s_rx_valid) begin
                saw = 1;
                got_s = s_rx;
                s_rx_clear = 1;
            end else
                s_rx_clear = 0;
        end
        @(posedge clk);
        s_rx_clear = 0;
        if (!cs_keep)
            while (busy) @(posedge clk);
        checks += 2;
        if (!saw || mask(got_s, nbits) !== mask(mtx, nbits)) begin
            errors++;
            $display("  [FAIL] slave rx=%h expected=%h (mode=%0d%0d nbits=%0d lsb=%0d div=%0d)",
                     got_s, mask(mtx, nbits), cpol, cpha, nbits, lsb_first, clkdiv);
        end
        if (mask(m_rx, nbits) !== mask(stx, nbits)) begin
            errors++;
            $display("  [FAIL] master rx=%h expected=%h (mode=%0d%0d nbits=%0d lsb=%0d div=%0d)",
                     m_rx, mask(stx, nbits), cpol, cpha, nbits, lsb_first, clkdiv);
        end
        n_xfer++;
        cov_mode[{cpol, cpha}]++;
        if (lsb_first) cov_lsb++; else cov_msb++;
        if (nbits==8) cov_w8++; else if (nbits==16) cov_w16++; else cov_w32++;
        if (cs_keep) cov_keep++;
        if (clkdiv<=2) cov_div[0]++; else if (clkdiv<=8) cov_div[1]++;
        else if (clkdiv<=32) cov_div[2]++; else cov_div[3]++;
    endtask

    int i, k, bits_sel, div_sel, burst;
    logic [31:0] a, b;

    initial begin
        errors = 0; checks = 0; n_xfer = 0;
        cov_lsb=0; cov_msb=0; cov_w8=0; cov_w16=0; cov_w32=0; cov_keep=0;
        foreach (cov_mode[i]) cov_mode[i]=0;
        foreach (cov_div[i]) cov_div[i]=0;

        repeat (4) @(posedge clk);
        rst_n = 1;
        enable = 1;
        @(posedge clk);

        // Directed warm-up: one transfer in each mode
        nbits = 8; clkdiv = 2; lsb_first = 0; cs_keep = 0;
        for (i = 0; i < 4; i++) begin
            cpol = i[1]; cpha = i[0];
            one_xfer(32'hA5, 32'h5A);
        end

        // Constrained-random group
        for (k = 0; k < 80; k++) begin
            i = $urandom(seed);
            seed = seed + 1;
            cpol = i[0];
            cpha = i[1];
            lsb_first = i[2];
            bits_sel = i[4:3];
            nbits = (bits_sel==0) ? 8 : (bits_sel==1) ? 16 : 32;
            div_sel = i[6:5];
            clkdiv = (div_sel==0) ? 16'd2 : (div_sel==1) ? 16'd3 : (div_sel==2) ? 16'd5 : 16'd8;
            cs_keep = 0;
            a = $urandom(seed); seed++;
            b = $urandom(seed); seed++;
            one_xfer(a, b);
        end

        // Random back-to-back bursts with CS held
        for (k = 0; k < 8; k++) begin
            i = $urandom(seed); seed++;
            cpol = i[0]; cpha = i[1]; lsb_first = i[2];
            nbits = i[3] ? 16 : 8;
            clkdiv = i[4] ? 16'd3 : 16'd2;
            cs_keep = 1;
            burst = 2 + (i[6:5]); // 2..5 words
            for (i = 0; i < burst; i++) begin
                a = $urandom(seed); seed++;
                b = $urandom(seed); seed++;
                one_xfer(a, b);
            end
            cs_keep = 0;
            @(posedge clk);
            while (busy) @(posedge clk);
        end

        $display("--------------------------------------------------");
        $display("Transfers: %0d   checks: %0d   errors: %0d", n_xfer, checks, errors);
        $display("Coverage counts:");
        $display("  mode 0/1/2/3 = %0d/%0d/%0d/%0d", cov_mode[0], cov_mode[1], cov_mode[2], cov_mode[3]);
        $display("  msb/lsb = %0d/%0d", cov_msb, cov_lsb);
        $display("  width 8/16/32 = %0d/%0d/%0d", cov_w8, cov_w16, cov_w32);
        $display("  cs_keep words = %0d", cov_keep);
        $display("  clkdiv 2 / 3-8 / 5 / 8+ bins = %0d/%0d/%0d/%0d",
                 cov_div[0], cov_div[1], cov_div[2], cov_div[3]);
        sva.report();
        if (errors == 0) $display("RESULT: ALL TESTS PASSED");
        else             $display("RESULT: FAILED");
        #100 $finish;
    end

    initial begin
        #200_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
