// spi_master_formal.v - bounded formal checks for the SPI master
// Author: B. Srishanth Reddy
`timescale 1ns/1ps
module spi_master_formal (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire abort_req,
    input  wire cpol,
    input  wire cpha,
    input  wire miso
);

    wire        busy, done, tx_ready, aborted, sclk, mosi, cs_n;
    wire [31:0] rx_data;

    spi_master #(.MAX_WIDTH(32)) dut (
        .clk(clk), .rst_n(rst_n),
        .enable(1'b1), .clkdiv(16'd2),
        .cpol(cpol), .cpha(cpha), .lsb_first(1'b0), .nbits(6'd8),
        .start(start), .cs_keep(1'b0), .abort_req(abort_req),
        .tx_data(32'hA5), .rx_data(rx_data),
        .busy(busy), .done(done), .tx_ready(tx_ready), .aborted(aborted),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

`ifdef FORMAL
    reg f_past_valid = 0;
    always @(posedge clk)
        f_past_valid <= 1'b1;

    // Reset for the first cycle.
    initial assume (!rst_n);
    always @(posedge clk) begin
        if (!f_past_valid)
            assume (!rst_n);
    end

    // CPOL and CPHA are configuration inputs. The checker holds them
    // steady so a mid-run change is not treated as a protocol bug.
    always @(posedge clk) begin
        if (f_past_valid && rst_n)
            assume ($stable(cpol) && $stable(cpha));
    end

    always @(posedge clk) begin
        if (f_past_valid && rst_n && $past(rst_n)) begin
            // F1: CS high implies SCLK == CPOL
            if (cs_n)
                assert (sclk == cpol);
            // F2: done is a one-cycle pulse
            if ($past(done) && $past(rst_n))
                assert (!done);
            // F3: done only while CS is low
            if (done)
                assert (!cs_n);
            // F4: start accepted => busy next cycle
            if ($past(start) && $past(tx_ready) && $past(rst_n) && !$past(abort_req))
                assert (busy);
        end
    end

    // Cover a completed word
    always @(posedge clk) begin
        if (f_past_valid && rst_n)
            cover (done);
    end
`endif

endmodule
