//      // verilator_coverage annotation
        // spi_loopback.v - on-chip master plus slave, MOSI/MISO crossed
        // Author: B. Srishanth Reddy
        //
        // Used by the loopback testbenches and by the iCEBreaker FPGA build.
        // The slave uses ASYNC=0 because both sides share the same clock.
        
        `timescale 1ns/1ps
        module spi_loopback #(
            parameter MAX_WIDTH = 32
        )(
 018449     input  wire                     clk,
%000001     input  wire                     rst_n,
%000001     input  wire                     enable,
~000020     input  wire [15:0]              clkdiv,
 000023     input  wire                     cpol,
 000019     input  wire                     cpha,
 000020     input  wire                     lsb_first,
~000022     input  wire [5:0]               nbits,
 000111     input  wire                     start,
%000008     input  wire                     cs_keep,
%000000     input  wire                     abort_req,
 000032     input  wire [MAX_WIDTH-1:0]     m_tx,
 000034     output wire [MAX_WIDTH-1:0]     m_rx,
 000034     input  wire [MAX_WIDTH-1:0]     s_tx,
 000031     output wire [MAX_WIDTH-1:0]     s_rx,
 000092     output wire                     busy,
 000111     output wire                     done,
 000105     output wire                     tx_ready,
%000000     output wire                     aborted,
 000111     output wire                     s_rx_valid,
 000093     output wire                     s_selected,
%000000     output wire                     s_overrun,
%000000     output wire                     s_mid_cs_abort,
 000111     input  wire                     s_rx_clear,
 002271     output wire                     sclk,
 000573     output wire                     mosi,
 000653     output wire                     miso,
 000093     output wire                     cs_n
        );
        
            /* verilator lint_off UNUSEDSIGNAL */
 000604     wire miso_core, miso_oe, s_busy;
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
 018256     assign miso = miso_oe ? miso_core : 1'b1;
        
        endmodule
        
