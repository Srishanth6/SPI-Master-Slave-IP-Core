// spi_monitor.v - passive SPI protocol checks (Icarus-friendly Verilog)
// Author: B. Srishanth Reddy
//
// Counts SCLK edges while CS is low and flags a mid-word CS rise when the
// edge count is odd (clock did not return to the idle level). MOSI and SCLK
// must not be X while CS is low.

`timescale 1ns/1ps
module spi_monitor #(
    parameter NAME = "spi"
)(
    input wire sclk,
    input wire mosi,
    input wire miso,
    input wire cs_n,
    input wire cpol,
    input wire en
);

    integer edges, words, mid_cs, errors, x_bus;
    reg sclk_d, cs_d;

    initial begin
        edges = 0; words = 0; mid_cs = 0; errors = 0; x_bus = 0;
        sclk_d = cpol; cs_d = 1'b1;
    end

    always @(sclk or cs_n or mosi or miso or en or cpol) begin
        if (en) begin
            if (cs_n === 1'b0) begin
                if (sclk === 1'bx || mosi === 1'bx) begin
                    x_bus = x_bus + 1;
                    errors = errors + 1;
                    $display("[%0s mon] X on SCLK/MOSI while CS low at t=%0t", NAME, $time);
                end
            end
        end
    end

    always @(posedge sclk or negedge sclk) begin
        if (en && cs_n === 1'b0)
            edges = edges + 1;
    end

    always @(posedge cs_n) begin
        if (en) begin
            if (edges % 2 != 0) begin
                mid_cs = mid_cs + 1;
                $display("[%0s mon] CS rose after %0d SCLK edges (odd) at t=%0t", NAME, edges, $time);
            end
            if (edges > 0 && (edges % 2 == 0))
                words = words + 1;
            if (sclk !== cpol) begin
                errors = errors + 1;
                $display("[%0s mon] SCLK not at CPOL when CS rose at t=%0t", NAME, $time);
            end
            edges = 0;
        end
    end

    always @(negedge cs_n) begin
        if (en) begin
            edges = 0;
            if (sclk !== cpol) begin
                errors = errors + 1;
                $display("[%0s mon] SCLK not at CPOL when CS fell at t=%0t", NAME, $time);
            end
        end
    end

endmodule
