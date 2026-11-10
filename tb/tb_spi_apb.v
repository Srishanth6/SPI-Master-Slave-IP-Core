// tb_spi_apb.v - APB register tests and a software-driven transfer
// Author: B. Srishanth Reddy
`timescale 1ns/1ps
module tb_spi_apb;
    localparam W = 32;
    localparam CTRL=8'h00, DIV=8'h04, TXD=8'h08, RXD=8'h0C, STAT=8'h10;

    reg pclk=0, presetn=0;
    always #10 pclk = ~pclk;

    reg psel=0, penable=0, pwrite=0;
    reg [7:0]  paddr=0;
    reg [31:0] pwdata=0;
    wire [31:0] prdata;
    wire pready, pslverr, irq;
    wire sclk, mosi, miso, cs_n;

    reg [31:0] s_tx=0;
    wire [31:0] s_rx;
    wire s_rx_valid, s_sel, s_ov, s_mid;
    wire miso_core, miso_oe;

    spi_apb #(.MAX_WIDTH(W)) dut (
        .pclk(pclk), .presetn(presetn),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata), .prdata(prdata),
        .pready(pready), .pslverr(pslverr), .irq(irq),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    spi_slave #(.MAX_WIDTH(W), .ASYNC(0)) u_s (
        .clk(pclk), .rst_n(presetn),
        .cpol(dut.cpol), .cpha(dut.cpha), .lsb_first(dut.lsb_first),
        .nbits(dut.nbits), .tx_data(s_tx), .rx_data(s_rx),
        .rx_valid(s_rx_valid), .selected(s_sel), .busy(),
        .overrun(s_ov), .mid_cs_abort(s_mid), .rx_clear(s_rx_valid),
        .sclk(sclk), .mosi(mosi), .cs_n(cs_n),
        .miso(miso_core), .miso_oe(miso_oe)
    );
    assign miso = miso_oe ? miso_core : 1'b1;

    spi_monitor #(.NAME("apb")) mon (
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n),
        .cpol(dut.cpol), .en(presetn)
    );

    integer errors=0, checks=0, tests_pass=0, tests_fail=0, test_err0=0;
    reg [7:0] test_id=0;
    reg [8*64-1:0] tname;
    reg [31:0] r;
    reg        saw_s;
    reg [31:0] s_lat;

    initial begin
        $dumpfile("waves/tb_spi_apb.vcd");
        $dumpvars(0, tb_spi_apb);
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
            test_id = id; tname = n; test_err0 = errors;
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
                $display("TEST %0d: %0s ... FAIL", test_id, tname);
            end
        end
    endtask

    task apb_w;
        input [7:0]  a;
        input [31:0] d;
        begin
            @(posedge pclk);
            psel=1; pwrite=1; penable=0; paddr=a; pwdata=d;
            @(posedge pclk);
            penable=1;
            @(posedge pclk);
            psel=0; penable=0; pwrite=0;
        end
    endtask

    task apb_r;
        input  [7:0]  a;
        output [31:0] d;
        begin
            @(posedge pclk);
            psel=1; pwrite=0; penable=0; paddr=a;
            @(posedge pclk);
            penable=1;
            @(posedge pclk);
            d = prdata;
            psel=0; penable=0;
        end
    endtask

    task wait_done_st;
        integer tmo;
        begin
            tmo = 0;
            apb_r(STAT, r);
            while (!r[1] && tmo < 100000) begin
                apb_r(STAT, r);
                tmo = tmo + 1;
            end
            check(r[1] === 1'b1, "STATUS.done set");
            tmo = 0;
            while (r[0] && tmo < 10000) begin
                apb_r(STAT, r);
                tmo = tmo + 1;
            end
            check(r[0] === 1'b0, "not busy after trail");
        end
    endtask

    initial begin
        repeat (4) @(posedge pclk);
        presetn = 1;
        @(posedge pclk);

        begin_test(1, "APB register access after reset");
        apb_r(STAT, r);
        $display("  STATUS reset = %02h (expected 00: disabled, idle)", r);
        check(r === 32'h00, "STATUS reset value");
        check(pready == 1 && pslverr == 0, "PREADY=1, PSLVERR=0");
        apb_w(DIV, 32'd4); apb_r(DIV, r); check(r === 32'd4, "CLKDIV rw");
        apb_w(CTRL, 32'h11); // enable + irq_en, mode 0, 8-bit
        apb_r(CTRL, r); check(r === 32'h11, "CTRL rw");
        apb_r(STAT, r); check(r[3] === 1'b1, "tx_ready after enable");
        apb_w(TXD, 32'hA5); // this also starts a transfer
        // clear the started transfer before the next tests? wait for it
        s_tx = 32'h5A;
        wait_done_st;
        apb_r(RXD, r);
        check(r[7:0] === 8'h5A, "first write also transferred");
        apb_w(STAT, 32'h02); // W1C done
        apb_r(STAT, r);
        check(r[1] === 1'b0, "done cleared");
        end_test;

        begin_test(2, "APB-driven 8-bit full-duplex transfer, irq on done");
        s_tx = 32'h3C;
        apb_w(CTRL, 32'h11);
        apb_w(TXD, 32'hC3);
        wait_done_st;
        check(irq === 1'b1, "irq raised on done");
        apb_r(RXD, r);
        check(r[7:0] === 8'h3C, "RXDATA from slave");
        check(s_rx[7:0] === 8'hC3, "slave received TXDATA");
        apb_w(STAT, 32'h02);
        apb_r(STAT, r);
        check(r[1] === 1'b0 && irq === 1'b0, "done W1C clears irq");
        end_test;

        begin_test(3, "16-bit and 32-bit words through APB");
        apb_w(CTRL, 32'h31); // enable, width=16, irq_en
        s_tx = 32'h55AA;
        apb_w(TXD, 32'hA55A);
        wait_done_st;
        apb_r(RXD, r); check(r[15:0] === 16'h55AA, "16-bit RX");
        check(s_rx[15:0] === 16'hA55A, "16-bit slave RX");
        apb_w(STAT, 32'h02);
        apb_w(CTRL, 32'h51); // width=32
        s_tx = 32'h01234567;
        apb_w(TXD, 32'h89ABCDEF);
        wait_done_st;
        apb_r(RXD, r); check(r === 32'h01234567, "32-bit RX");
        check(s_rx === 32'h89ABCDEF, "32-bit slave RX");
        apb_w(STAT, 32'h02);
        end_test;

        begin_test(4, "TXDATA while busy is rejected (cmd_err)");
        apb_w(CTRL, 32'h11);
        s_tx = 32'h00;
        apb_w(TXD, 32'h11);
        // immediately write again without waiting
        apb_w(TXD, 32'h22);
        apb_r(STAT, r);
        check(r[6] === 1'b1, "cmd_err set");
        check(irq === 1'b1, "irq on cmd_err");
        wait_done_st;
        apb_w(STAT, 32'h42); // clear cmd_err and done
        apb_r(STAT, r);
        check(r[6] === 1'b0 && r[1] === 1'b0, "cmd_err and done cleared");
        end_test;

        begin_test(5, "Illegal width 11 sets cmd_err, width unchanged");
        apb_w(CTRL, 32'h11); // width 00 = 8
        apb_w(CTRL, 32'h71); // width 11, enable, irq_en
        apb_r(CTRL, r);
        check(r[6:5] === 2'b00, "width left at 8");
        apb_r(STAT, r);
        check(r[6] === 1'b1, "cmd_err on bad width");
        apb_w(STAT, 32'h40);
        end_test;

        begin_test(6, "Abort through CTRL bit 8");
        apb_w(CTRL, 32'h11);
        s_tx = 32'hFF;
        apb_w(TXD, 32'h81);
        apb_w(CTRL, 32'h111); // enable + abort
        repeat (8) @(posedge pclk);
        apb_r(STAT, r);
        check(r[5] === 1'b1, "STATUS.aborted");
        check(r[0] === 1'b0, "not busy after abort");
        check(cs_n === 1'b1, "CS released after abort");
        apb_w(STAT, 32'h20);
        end_test;

        begin_test(7, "TXDATA rejected when enable=0");
        apb_w(CTRL, 32'h00);
        apb_w(TXD, 32'h55);
        apb_r(STAT, r);
        check(r[6] === 1'b1, "cmd_err when disabled");
        check(r[0] === 1'b0, "did not start");
        apb_w(STAT, 32'h40);
        end_test;

        check(mon.errors == 0, "protocol monitor errors");
        $display("--------------------------------------------------");
        $display("SUMMARY tb_spi_apb: %0d/%0d tests PASS, %0d checks, %0d errors",
                 tests_pass, tests_pass+tests_fail, checks, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED");
        else             $display("RESULT: FAILED");
        #1000 $finish;
    end

    initial begin
        #20_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
