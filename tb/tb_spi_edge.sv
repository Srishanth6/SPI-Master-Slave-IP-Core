// tb_spi_edge.sv - directed edge cases
// Author: B. Srishanth Reddy
`timescale 1ns/1ps
module tb_spi_edge;
    localparam W = 32;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;

    logic             enable = 0;
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

    int errors = 0, checks = 0, tests_pass = 0, tests_fail = 0, test_err0 = 0;
    logic [7:0] test_id = 0;
    string tname;

    initial begin
        $dumpfile("waves/tb_spi_edge.vcd");
        $dumpvars(0, tb_spi_edge);
    end

    task automatic check(input bit cond, input string msg);
        checks++;
        if (!cond) begin
            errors++;
            $display("  [FAIL] %s  (t=%0t)", msg, $time);
        end
    endtask

    task automatic begin_test(input int id, input string n);
        test_id = id[7:0]; tname = n; test_err0 = errors;
        $display("TEST %0d: %s", id, n);
    endtask

    task automatic end_test();
        if (errors == test_err0) begin
            tests_pass++;
            $display("TEST %0d: %s ... PASS", test_id, tname);
        end else begin
            tests_fail++;
            $display("TEST %0d: %s ... FAIL", test_id, tname);
        end
    endtask

    task automatic xfer(input logic [31:0] mtx, input logic [31:0] stx);
        s_tx = stx; m_tx = mtx;
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        while (!done) @(posedge clk);
        if (!cs_keep) while (busy) @(posedge clk);
    endtask

    integer i, cycles;
    logic   saw_abort, saw_mid, saw_valid;
    logic   sclk_prev;
    integer halfs;

    // Extra slave for "CS tied" tests
    logic [W-1:0] t_rx;
    logic         t_valid, t_sel, t_mid, t_oe, t_miso;
    logic         t_sclk, t_mosi, t_cs;

    spi_slave #(.MAX_WIDTH(W), .ASYNC(0)) u_tied (
        .clk, .rst_n, .cpol, .cpha, .lsb_first, .nbits,
        .tx_data(32'hA5), .rx_data(t_rx), .rx_valid(t_valid),
        .selected(t_sel), .busy(), .overrun(), .mid_cs_abort(t_mid),
        .rx_clear(1'b1), .sclk(t_sclk), .mosi(t_mosi), .cs_n(t_cs),
        .miso(t_miso), .miso_oe(t_oe)
    );

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1; enable = 1;
        @(posedge clk);

        begin_test(1, "abort mid-word releases CS and sets aborted");
        cpol=0; cpha=0; nbits=8; clkdiv=4; cs_keep=0; s_tx=32'hFF; m_tx=32'h81;
        @(posedge clk); start=1; @(posedge clk); start=0;
        repeat (8) @(posedge clk); // mid-transfer
        abort=1; @(posedge clk); abort=0;
        repeat (6) @(posedge clk);
        check(aborted === 1'b1, "aborted flag");
        check(cs_n === 1'b1, "CS released");
        check(busy === 1'b0, "not busy after abort");
        end_test;

        begin_test(2, "word lengths 1, 4, 8, 16, 32");
        clkdiv=2; cpol=0; cpha=0; lsb_first=0;
        nbits=1;  xfer(32'h1, 32'h1); check(m_rx[0]===1'b1 && dut.s_rx[0]===1'b1, "1-bit");
        nbits=4;  xfer(32'hA, 32'h5); check(m_rx[3:0]===4'h5 && dut.s_rx[3:0]===4'hA, "4-bit");
        nbits=8;  xfer(32'h3C, 32'hC3); check(m_rx[7:0]===8'hC3 && dut.s_rx[7:0]===8'h3C, "8-bit");
        nbits=16; xfer(32'h1234, 32'hABCD); check(m_rx[15:0]===16'hABCD, "16-bit");
        nbits=32; xfer(32'h01234567, 32'h89ABCDEF); check(m_rx===32'h89ABCDEF, "32-bit");
        end_test;

        begin_test(3, "clkdiv=0 is treated as 1 (SCLK half-period)");
        nbits=8; cpol=0; cpha=0; clkdiv=0;
        // Do not require loopback at clkdiv=1; only check the half-period.
        m_tx=32'hA5; s_tx=32'h00;
        @(posedge clk); start=1; @(posedge clk); start=0;
        // Wait until CS falls, then measure a low or high half
        while (cs_n) @(posedge clk);
        while (sclk == cpol) @(posedge clk); // wait leading
        halfs = 1; // the cycle of the edge
        // count cycles until trailing
        @(posedge clk);
        cycles = 1;
        while (sclk != cpol) begin
            @(posedge clk);
            cycles++;
        end
        $display("  measured SCLK high time after clkdiv=0: %0d clocks (expected 1)", cycles);
        check(cycles == 1, "clkdiv=0 clamps to half-period of 1 clock");
        while (busy) @(posedge clk);
        end_test;

        begin_test(4, "clkdiv=65535, one 8-bit word");
        clkdiv=16'd65535; nbits=8; cpol=0; cpha=0; s_tx=32'h5A; m_tx=32'hA5;
        @(posedge clk); start=1; @(posedge clk); start=0;
        while (!done) @(posedge clk);
        while (busy) @(posedge clk);
        check(dut.s_rx[7:0]===8'hA5, "slave got A5 at max divider");
        check(m_rx[7:0]===8'h5A, "master got 5A at max divider");
        end_test;

        begin_test(5, "slave with CS tied high never selects or drives");
        t_cs = 1'b1; t_sclk = 0; t_mosi = 0;
        // Wiggle a fake clock
        repeat (16) begin
            @(posedge clk); t_sclk = ~t_sclk;
        end
        check(t_sel === 1'b0, "not selected");
        check(t_oe === 1'b0, "MISO not driven");
        check(t_valid === 1'b0, "no rx_valid");
        end_test;

        begin_test(6, "slave with CS tied low frames words by bit count");
        cpol=0; cpha=0; nbits=8; lsb_first=0;
        t_cs = 1'b0; t_sclk = 0; t_mosi = 0;
        repeat (8) @(posedge clk); // allow arm after reset-style CS
        saw_valid = 0;
        // 8 bits, MSB first, send 0xC3 = 1100_0011, CPHA=0: data valid before first rise
        for (i = 7; i >= 0; i--) begin
            t_mosi = (8'hC3 >> i) & 1'b1;
            repeat (2) @(posedge clk);
            t_sclk = 1; // leading
            repeat (2) @(posedge clk);
            t_sclk = 0; // trailing
            if (t_valid) saw_valid = 1;
            repeat (2) @(posedge clk);
        end
        repeat (8) begin
            @(posedge clk);
            if (t_valid) begin
                saw_valid = 1;
                $display("  tied-low slave rx=%02h", t_rx[7:0]);
            end
        end
        check(saw_valid === 1'b1, "rx_valid with CS tied low");
        check(t_rx[7:0] === 8'hC3, "data framed with CS tied low");
        t_cs = 1'b1;
        end_test;

        begin_test(7, "reset in the middle of a transfer");
        clkdiv=2; nbits=8; enable=1; cpol=0; cpha=0;
        m_tx=32'hFF; s_tx=32'h00;
        @(posedge clk); start=1; @(posedge clk); start=0;
        repeat (6) @(posedge clk);
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        check(cs_n === 1'b1, "CS high after reset");
        check(busy === 1'b0, "idle after reset");
        xfer(32'hA5, 32'h5A);
        check(m_rx[7:0]===8'h5A && dut.s_rx[7:0]===8'hA5, "transfer after reset");
        end_test;

        begin_test(8, "overrun when a second word arrives unread");
        clkdiv=2; nbits=8; cs_keep=1;
        // Don't clear slave RX between two words
        s_tx=32'h11; m_tx=32'h22;
        @(posedge clk); start=1; @(posedge clk); start=0;
        while (!done) @(posedge clk);
        s_tx=32'h33; m_tx=32'h44;
        @(posedge clk); start=1; @(posedge clk); start=0;
        while (!done) @(posedge clk);
        repeat (4) @(posedge clk);
        check(s_overrun === 1'b1, "slave overrun set");
        cs_keep=0;
        while (busy) @(posedge clk);
        end_test;

        sva.report();
        $display("--------------------------------------------------");
        $display("SUMMARY tb_spi_edge: %0d/%0d tests PASS, %0d checks, %0d errors",
                 tests_pass, tests_pass+tests_fail, checks, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED");
        else             $display("RESULT: FAILED");
        #1000 $finish;
    end

    initial begin
        #2_000_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
