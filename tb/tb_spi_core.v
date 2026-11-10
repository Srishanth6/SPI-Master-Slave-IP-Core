// tb_spi_core.v - directed master <-> slave loopback tests
// Author: B. Srishanth Reddy
`timescale 1ns/1ps
module tb_spi_core;
    localparam W = 32;

    reg clk = 0, rst_n = 0;
    always #10 clk = ~clk; // 50 MHz

    reg             enable = 0;
    reg [15:0]      clkdiv = 16'd2;
    reg             cpol = 0, cpha = 0, lsb_first = 0;
    reg [5:0]       nbits = 6'd8;
    reg             start = 0, cs_keep = 0, abort = 0;
    reg [W-1:0]     m_tx = 0, s_tx = 0;
    wire [W-1:0]    m_rx, s_rx;
    wire            busy, done, tx_ready, aborted;
    wire            s_rx_valid, s_selected, s_overrun, s_mid_cs_abort;
    reg             s_rx_clear = 0;
    wire            sclk, mosi, miso, cs_n;

    spi_loopback #(.MAX_WIDTH(W)) dut (
        .clk(clk), .rst_n(rst_n),
        .enable(enable), .clkdiv(clkdiv),
        .cpol(cpol), .cpha(cpha), .lsb_first(lsb_first), .nbits(nbits),
        .start(start), .cs_keep(cs_keep), .abort_req(abort),
        .m_tx(m_tx), .m_rx(m_rx), .s_tx(s_tx), .s_rx(s_rx),
        .busy(busy), .done(done), .tx_ready(tx_ready), .aborted(aborted),
        .s_rx_valid(s_rx_valid), .s_selected(s_selected),
        .s_overrun(s_overrun), .s_mid_cs_abort(s_mid_cs_abort),
        .s_rx_clear(s_rx_clear),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    spi_monitor #(.NAME("core")) mon (
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n),
        .cpol(cpol), .en(rst_n)
    );

    integer errors, checks, tests_pass, tests_fail, test_err0;
    integer cove_mode0, cove_mode1, cove_mode2, cove_mode3;
    integer cove_msb, cove_lsb, cove_w8, cove_w16, cove_w32;
    integer cove_keep, cove_full, cove_divmin, cove_divmid;
    reg [7:0] test_id;
    reg [8*64-1:0] tname;
    reg             saw_s_valid;
    reg [W-1:0]     s_rx_latched;

    initial begin
        $dumpfile("waves/tb_spi_core.vcd");
        $dumpvars(0, tb_spi_core);
    end

    task check;
        input cond;
        input [8*80-1:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("  [FAIL] %0s  (t=%0t)", msg, $time);
            end
        end
    endtask

    task begin_test;
        input [7:0] id;
        input [8*64-1:0] n;
        begin
            test_id = id;
            tname = n;
            test_err0 = errors;
            $display("TEST %0d: %0s", id, n);
        end
    endtask

    task end_test;
        begin
            if (errors == test_err0) begin
                tests_pass = tests_pass + 1;
                $display("TEST %0d: %0s ... PASS", test_id, tname);
            end else begin
                tests_fail = tests_fail + 1;
                $display("TEST %0d: %0s ... FAIL (%0d new errors)", test_id, tname, errors - test_err0);
            end
        end
    endtask

    task wait_done;
        integer timeout;
        begin
            timeout = 0;
            while (!done && timeout < 2000000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            check(done === 1'b1, "timeout waiting for done");
        end
    endtask

    // One full-duplex word. Slave TX must be set before start (or held).
    task xfer_word;
        input [W-1:0] mtx;
        input [W-1:0] stx;
        begin
            s_tx = stx;
            m_tx = mtx;
            saw_s_valid = 0;
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            while (!done) begin
                @(posedge clk);
                if (s_rx_valid) begin
                    saw_s_valid = 1;
                    s_rx_latched = s_rx;
                    s_rx_clear = 1;
                end else
                    s_rx_clear = 0;
            end
            @(posedge clk);
            s_rx_clear = 0;
            if (!cs_keep) begin
                // done is one half-period before CS goes high
                while (busy) @(posedge clk);
            end
        end
    endtask

    function [W-1:0] mask_word;
        input [W-1:0] data;
        input [5:0]   bits;
        begin
            if (bits >= W)
                mask_word = data;
            else
                mask_word = data & (({W{1'b1}}) >> (W - bits));
        end
    endfunction

    task check_xfer;
        input [W-1:0] mtx;
        input [W-1:0] stx;
        reg [W-1:0] em, es;
        begin
            em = mask_word(mtx, nbits);
            es = mask_word(stx, nbits);
            check(saw_s_valid === 1'b1, "slave rx_valid seen");
            check(s_rx_latched === em, "slave received master TX");
            check(mask_word(m_rx, nbits) === es, "master received slave TX");
            if (s_rx_latched !== em)
                $display("    slave rx=%h expected=%h", s_rx_latched, em);
            if (mask_word(m_rx, nbits) !== es)
                $display("    master rx=%h expected=%h", m_rx, es);
        end
    endtask

    task do_xfer;
        input [W-1:0] mtx;
        input [W-1:0] stx;
        begin
            xfer_word(mtx, stx);
            check_xfer(mtx, stx);
            cove_full = cove_full + 1;
            if (nbits == 8)  cove_w8  = cove_w8  + 1;
            if (nbits == 16) cove_w16 = cove_w16 + 1;
            if (nbits == 32) cove_w32 = cove_w32 + 1;
            if (lsb_first) cove_lsb = cove_lsb + 1;
            else           cove_msb = cove_msb + 1;
            case ({cpol, cpha})
            2'b00: cove_mode0 = cove_mode0 + 1;
            2'b01: cove_mode1 = cove_mode1 + 1;
            2'b10: cove_mode2 = cove_mode2 + 1;
            2'b11: cove_mode3 = cove_mode3 + 1;
            endcase
            if (clkdiv <= 2) cove_divmin = cove_divmin + 1;
            else             cove_divmid = cove_divmid + 1;
        end
    endtask

    integer i, mode;
    reg [W-1:0] a, b;

    initial begin
        errors = 0; checks = 0; tests_pass = 0; tests_fail = 0;
        cove_mode0 = 0; cove_mode1 = 0; cove_mode2 = 0; cove_mode3 = 0;
        cove_msb = 0; cove_lsb = 0; cove_w8 = 0; cove_w16 = 0; cove_w32 = 0;
        cove_keep = 0; cove_full = 0; cove_divmin = 0; cove_divmid = 0;
        test_id = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        enable = 1;
        @(posedge clk);

        // ---- 1-4: all four SPI modes, 8-bit, MSB first, clkdiv=2 ----
        nbits = 8; lsb_first = 0; clkdiv = 2; cs_keep = 0;
        for (mode = 0; mode < 4; mode = mode + 1) begin
            cpol = mode[1];
            cpha = mode[0];
            begin_test(mode + 1, {"mode ", 8'd48+mode[1], 8'd48+mode[0], " 8-bit MSB clkdiv=2"});
            do_xfer(32'hA5, 32'h5A);
            do_xfer(32'h00, 32'hFF);
            do_xfer(32'hFF, 32'h00);
            do_xfer(32'h81, 32'h7E);
            check(cs_n === 1'b1, "CS released after word");
            end_test;
        end

        // ---- 5: LSB first, all modes ----
        begin_test(5, "LSB first, all four modes, 8-bit");
        lsb_first = 1; nbits = 8; clkdiv = 2;
        for (mode = 0; mode < 4; mode = mode + 1) begin
            cpol = mode[1]; cpha = mode[0];
            do_xfer(32'hE1, 32'h1E);
        end
        end_test;

        // ---- 6: 16-bit and 32-bit words ----
        begin_test(6, "16-bit and 32-bit words, modes 0 and 3");
        lsb_first = 0; clkdiv = 2;
        nbits = 16; cpol = 0; cpha = 0;
        do_xfer(32'hA5C3, 32'h5A3C);
        nbits = 16; cpol = 1; cpha = 1;
        do_xfer(32'h0123, 32'h89AB);
        nbits = 32; cpol = 0; cpha = 0;
        do_xfer(32'hDEADBEEF, 32'h12345678);
        nbits = 32; cpol = 1; cpha = 1; lsb_first = 1;
        do_xfer(32'hCAFEBABE, 32'h13579BDF);
        end_test;

        // ---- 7: back-to-back with CS held low ----
        begin_test(7, "CS held low for three back-to-back 8-bit words");
        lsb_first = 0; nbits = 8; cpol = 0; cpha = 0; clkdiv = 2;
        cs_keep = 1;
        xfer_word(32'h11, 32'hA0);
        check_xfer(32'h11, 32'hA0);
        check(cs_n === 1'b0, "CS still low after word 1");
        xfer_word(32'h22, 32'hB1);
        check_xfer(32'h22, 32'hB1);
        check(cs_n === 1'b0, "CS still low after word 2");
        xfer_word(32'h33, 32'hC2);
        check_xfer(32'h33, 32'hC2);
        // release CS
        cs_keep = 0;
        @(posedge clk);
        // may already be in WAIT; dropping cs_keep should raise CS
        repeat (8) @(posedge clk);
        check(cs_n === 1'b1, "CS released after cs_keep cleared");
        cove_keep = cove_keep + 3;
        end_test;

        // ---- 8: different clock divisors ----
        begin_test(8, "clkdiv = 2, 3, 8, 16 (min supported is 2)");
        lsb_first = 0; nbits = 8; cpol = 0; cpha = 0; cs_keep = 0;
        clkdiv = 2; do_xfer(32'h36, 32'hC9);
        clkdiv = 3; do_xfer(32'h36, 32'hC9);
        clkdiv = 8; do_xfer(32'h36, 32'hC9);
        clkdiv = 16; do_xfer(32'h36, 32'hC9);
        end_test;

        // ---- 9: full-duplex walking patterns, mode 0 and 1 ----
        begin_test(9, "walking ones/zeros, modes 0 and 1");
        clkdiv = 2; nbits = 8; lsb_first = 0; cs_keep = 0;
        cpol = 0; cpha = 0;
        for (i = 0; i < 8; i = i + 1)
            do_xfer(32'd1 << i, 32'd1 << (7 - i));
        cpha = 1;
        for (i = 0; i < 8; i = i + 1)
            do_xfer(~(32'd1 << i) & 32'hFF, 32'd1 << i);
        end_test;

        // ---- 10: last bit = 1 in every mode, 8 and 32 bit ----
        begin_test(10, "odd LSB in all modes, 8-bit and 32-bit");
        lsb_first = 0; clkdiv = 2; cs_keep = 0;
        nbits = 8;
        for (mode = 0; mode < 4; mode = mode + 1) begin
            cpol = mode[1]; cpha = mode[0];
            do_xfer(32'h01, 32'h01);
            do_xfer(32'hFF, 32'h81);
        end
        nbits = 32; cpol = 0; cpha = 0;
        do_xfer(32'h01234567, 32'h89ABCDEF);
        nbits = 32; cpol = 0; cpha = 1;
        do_xfer(32'h01234567, 32'h89ABCDEF);
        end_test;

        $display("--------------------------------------------------");
        $display("Functional coverage (directed, transfer counts):");
        $display("  modes 0/1/2/3 = %0d/%0d/%0d/%0d", cove_mode0, cove_mode1, cove_mode2, cove_mode3);
        $display("  msb/lsb = %0d/%0d  width 8/16/32 = %0d/%0d/%0d", cove_msb, cove_lsb, cove_w8, cove_w16, cove_w32);
        $display("  cs_keep words = %0d  full-duplex = %0d  div<=2 = %0d  div>2 = %0d",
                 cove_keep, cove_full, cove_divmin, cove_divmid);
        $display("  monitor: words=%0d mid_cs=%0d errors=%0d x_bus=%0d",
                 mon.words, mon.mid_cs, mon.errors, mon.x_bus);
        check(mon.errors == 0, "protocol monitor errors");
        $display("--------------------------------------------------");
        $display("SUMMARY tb_spi_core: %0d/%0d tests PASS, %0d checks, %0d errors",
                 tests_pass, tests_pass + tests_fail, checks, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED");
        else             $display("RESULT: FAILED");
        #1000 $finish;
    end

    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
