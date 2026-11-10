// spi_loopback.v - on-chip master plus slave, MOSI/MISO crossed
// Author: B. Srishanth Reddy
//
// Used by the loopback testbenches and by the iCEBreaker FPGA build.
// The slave uses ASYNC=0 because both sides share the same clock.

`timescale 1ns/1ps
module spi_loopback #(
    parameter MAX_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     enable,
    input  wire [15:0]              clkdiv,
    input  wire                     cpol,
    input  wire                     cpha,
    input  wire                     lsb_first,
    input  wire [5:0]               nbits,
    input  wire                     start,
    input  wire                     cs_keep,
    input  wire                     abort_req,
    input  wire [MAX_WIDTH-1:0]     m_tx,
    output wire [MAX_WIDTH-1:0]     m_rx,
    input  wire [MAX_WIDTH-1:0]     s_tx,
    output wire [MAX_WIDTH-1:0]     s_rx,
    output wire                     busy,
    output wire                     done,
    output wire                     tx_ready,
    output wire                     aborted,
    output wire                     s_rx_valid,
    output wire                     s_selected,
    output wire                     s_overrun,
    output wire                     s_mid_cs_abort,
    input  wire                     s_rx_clear,
    output wire                     sclk,
    output wire                     mosi,
    output wire                     miso,
    output wire                     cs_n
);

    /* verilator lint_off UNUSEDSIGNAL */
    wire miso_core, miso_oe, s_busy;
    /* verilator lint_on UNUSEDSIGNAL */

    spi_master #(.MAX_WIDTH(MAX_WIDTH)) u_m (
        .clk(clk), .rst_n(rst_n),
        .enable(enable), .clkdiv(clkdiv),
        .cpol(cpol), .cpha(cpha), .lsb_first(lsb_first),
        .nbits(nbits), .start(start), .cs_keep(cs_keep), .abort_req(abort_req),
        .tx_data(m_tx), .rx_data(m_rx),
        .busy(busy), .done(done), .tx_ready(tx_ready), .aborted(aborted),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    spi_slave #(.MAX_WIDTH(MAX_WIDTH), .ASYNC(0)) u_s (
        .clk(clk), .rst_n(rst_n),
        .cpol(cpol), .cpha(cpha), .lsb_first(lsb_first), .nbits(nbits),
        .tx_data(s_tx), .rx_data(s_rx), .rx_valid(s_rx_valid),
        .selected(s_selected), .busy(s_busy), .overrun(s_overrun),
        .mid_cs_abort(s_mid_cs_abort), .rx_clear(s_rx_clear),
        .sclk(sclk), .mosi(mosi), .cs_n(cs_n),
        .miso(miso_core), .miso_oe(miso_oe)
    );

    // Pull MISO up when the slave is not driving it.
    assign miso = miso_oe ? miso_core : 1'b1;

endmodule
