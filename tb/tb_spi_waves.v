// tb_spi_waves.v - one short transfer in each SPI mode, for waveform plots
// Author: B. Srishanth Reddy
`timescale 1ns/1ps
module tb_spi_waves;
    localparam W = 32;
    reg clk=0, rst_n=0, enable=0, start=0, cs_keep=0, abort=0, cpol=0, cpha=0, lsb=0;
    reg [15:0] clkdiv=16'd4;
    reg [5:0] nbits=6'd8;
    reg [W-1:0] m_tx=0, s_tx=0;
    wire [W-1:0] m_rx, s_rx;
    wire busy, done, tx_ready, aborted, s_rx_valid, s_sel, s_ov, s_mid;
    wire sclk, mosi, miso, cs_n;
    integer mode;

    always #10 clk = ~clk;

    spi_loopback #(.MAX_WIDTH(W)) dut (
        .clk(clk), .rst_n(rst_n), .enable(enable), .clkdiv(clkdiv),
        .cpol(cpol), .cpha(cpha), .lsb_first(lsb), .nbits(nbits),
        .start(start), .cs_keep(cs_keep), .abort_req(abort),
        .m_tx(m_tx), .m_rx(m_rx), .s_tx(s_tx), .s_rx(s_rx),
        .busy(busy), .done(done), .tx_ready(tx_ready), .aborted(aborted),
        .s_rx_valid(s_rx_valid), .s_selected(s_sel), .s_overrun(s_ov),
        .s_mid_cs_abort(s_mid), .s_rx_clear(s_rx_valid),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    initial begin
        $dumpfile("waves/tb_spi_waves.vcd");
        $dumpvars(0, tb_spi_waves);
        repeat (4) @(posedge clk);
        rst_n = 1; enable = 1;
        m_tx = 32'hA5; s_tx = 32'h5A;
        for (mode = 0; mode < 4; mode = mode + 1) begin
            cpol = mode[1]; cpha = mode[0];
            @(posedge clk); start = 1;
            @(posedge clk); start = 0;
            while (busy) @(posedge clk);
            repeat (8) @(posedge clk);
        end
        #100 $finish;
    end
endmodule
