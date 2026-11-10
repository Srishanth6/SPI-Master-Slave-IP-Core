// spi_apb.v - AMBA 3 APB register wrapper around spi_master
// Author: B. Srishanth Reddy
//
// 0x00 CTRL    [0] enable  [1] cpol  [2] cpha  [3] lsb_first  [4] irq_en
//              [6:5] width (00=8, 01=16, 10=32)  [7] cs_keep  [8] abort (WO)
// 0x04 CLKDIV  [15:0]  clocks per SCLK half-period, reset 8 (f_sclk = pclk/16)
// 0x08 TXDATA  [31:0]  write starts a transfer when enable=1 and tx_ready=1
// 0x0C RXDATA  [31:0]  RO, last received word; a read clears STATUS.rx_ready
// 0x10 STATUS  [0] busy  [1] done (W1C)  [2] rx_ready (W1C)  [3] tx_ready
//              [4] overrun (W1C)  [5] aborted (W1C)  [6] cmd_err (W1C)
// irq = CTRL.irq_en & (done | cmd_err | aborted | overrun)
//
// A TXDATA write while the master is not ready is rejected and sets cmd_err.
// A CTRL write of an unsupported width also sets cmd_err and leaves the
// previous width in place.

`timescale 1ns/1ps
module spi_apb #(
    parameter MAX_WIDTH = 32
)(
    input  wire        pclk,
    input  wire        presetn,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [7:0]  paddr,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,
    output wire        irq,
    output wire        sclk,
    output wire        mosi,
    input  wire        miso,
    output wire        cs_n
);

    reg        enable, cpol, cpha, lsb_first, irq_en, cs_keep;
    reg [1:0]  width;
    reg [15:0] clkdiv;
    reg [31:0] txdata;
    reg        start, abort_req;
    reg        done_st, rx_ready_st, overrun_st, aborted_st, cmd_err;

    wire [31:0] rx_data;
    wire        busy, done, tx_ready, aborted;

    wire [5:0] nbits = (width == 2'd1) ? 6'd16 :
                       (width == 2'd2) ? 6'd32 : 6'd8;

    assign pready  = 1'b1;
    assign pslverr = 1'b0;
    wire aligned = (paddr[1:0] == 2'b00);
    wire wr = psel & penable & pwrite & aligned;
    wire rd = psel & penable & ~pwrite; // reads still return data even if not aligned

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            enable      <= 1'b0;
            cpol        <= 1'b0;
            cpha        <= 1'b0;
            lsb_first   <= 1'b0;
            irq_en      <= 1'b0;
            cs_keep     <= 1'b0;
            width       <= 2'd0;
            clkdiv      <= 16'd8;
            txdata      <= 32'd0;
            start       <= 1'b0;
            abort_req   <= 1'b0;
            done_st     <= 1'b0;
            rx_ready_st <= 1'b0;
            overrun_st  <= 1'b0;
            aborted_st  <= 1'b0;
            cmd_err     <= 1'b0;
        end else begin
            start     <= 1'b0;
            abort_req <= 1'b0;
            if (done)
                done_st <= 1'b1;
            if (done) begin
                if (rx_ready_st)
                    overrun_st <= 1'b1;
                rx_ready_st <= 1'b1;
            end
            if (aborted)
                aborted_st <= 1'b1;

            if (wr) begin
                case (paddr[7:2])
                6'h0: begin
                    enable    <= pwdata[0];
                    cpol      <= pwdata[1];
                    cpha      <= pwdata[2];
                    lsb_first <= pwdata[3];
                    irq_en    <= pwdata[4];
                    cs_keep   <= pwdata[7];
                    if (pwdata[6:5] == 2'b11)
                        cmd_err <= 1'b1;
                    else
                        width   <= pwdata[6:5];
                    if (pwdata[8])
                        abort_req <= 1'b1;
                end
                6'h1: clkdiv <= pwdata[15:0];
                6'h2: begin
                    txdata <= pwdata;
                    if (!enable || !tx_ready)
                        cmd_err <= 1'b1;
                    else
                        start <= 1'b1;
                end
                6'h4: begin
                    if (pwdata[1]) done_st     <= 1'b0;
                    if (pwdata[2]) rx_ready_st <= 1'b0;
                    if (pwdata[4]) overrun_st  <= 1'b0;
                    if (pwdata[5]) aborted_st  <= 1'b0;
                    if (pwdata[6]) cmd_err     <= 1'b0;
                end
                default: ;
                endcase
            end
            if (rd && (paddr[7:2] == 6'h3))
                rx_ready_st <= 1'b0;
        end
    end

    always @* begin
        case (paddr[7:2])
        6'h0: prdata = {23'd0, 1'b0, cs_keep, width, irq_en, lsb_first, cpha, cpol, enable};
        6'h1: prdata = {16'd0, clkdiv};
        6'h2: prdata = txdata;
        6'h3: prdata = rx_data;
        6'h4: prdata = {25'd0, cmd_err, aborted_st, overrun_st, tx_ready, rx_ready_st, done_st, busy};
        default: prdata = 32'd0;
        endcase
    end

    assign irq = irq_en & (done_st | cmd_err | aborted_st | overrun_st);

    spi_master #(.MAX_WIDTH(MAX_WIDTH)) u_master (
        .clk(pclk), .rst_n(presetn),
        .enable(enable), .clkdiv(clkdiv),
        .cpol(cpol), .cpha(cpha), .lsb_first(lsb_first),
        .nbits(nbits), .start(start), .cs_keep(cs_keep), .abort_req(abort_req),
        .tx_data(txdata), .rx_data(rx_data),
        .busy(busy), .done(done), .tx_ready(tx_ready), .aborted(aborted),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

endmodule
