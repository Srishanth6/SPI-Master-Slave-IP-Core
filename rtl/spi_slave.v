// spi_slave.v - SPI slave
// Author: B. Srishanth Reddy
//
// When ASYNC=1, SCLK, CS and MOSI go through two flip-flops into the system
// clock domain. The SCLK half-period should then be at least two system
// clocks so that every edge is seen. When ASYNC=0 the inputs are delayed by
// one flip-flop only, which is the right setting if the master is on the
// same clock.
//
// MISO is driven only while CS is low. A word is complete after nbits
// samples; rx_valid is a one-cycle pulse. If CS rises before that, the
// partial word is dropped and mid_cs_abort pulses. If CS is tied low,
// words are framed by the bit count alone.

`timescale 1ns/1ps
module spi_slave #(
    parameter MAX_WIDTH = 32,
    parameter ASYNC     = 1
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     cpol,
    input  wire                     cpha,
    input  wire                     lsb_first,
    input  wire [5:0]               nbits,
    input  wire [MAX_WIDTH-1:0]     tx_data,
    output reg  [MAX_WIDTH-1:0]     rx_data,
    output reg                      rx_valid,
    output wire                     selected,
    output reg                      busy,
    output reg                      overrun,
    output reg                      mid_cs_abort,
    input  wire                     rx_clear,
    input  wire                     sclk,
    input  wire                     mosi,
    input  wire                     cs_n,
    output reg                      miso,
    output wire                     miso_oe
);

    localparam IW = $clog2(MAX_WIDTH + 1);
    localparam BW = $clog2(MAX_WIDTH);

    wire [5:0] bits_clamped = (nbits == 6'd0) ? 6'd1 :
                              (nbits > MAX_WIDTH[5:0]) ? MAX_WIDTH[5:0] : nbits;

    reg sclk_s0, sclk_s1, cs_s0, cs_s1, mosi_s0, mosi_s1;
    reg sclk_d, cs_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_s0 <= 1'b0;
            sclk_s1 <= 1'b0;
            cs_s0   <= 1'b1;
            cs_s1   <= 1'b1;
            mosi_s0 <= 1'b0;
            mosi_s1 <= 1'b0;
            sclk_d  <= 1'b0;
            cs_d    <= 1'b1;
        end else begin
            sclk_s0 <= sclk;
            sclk_s1 <= sclk_s0;
            cs_s0   <= cs_n;
            cs_s1   <= cs_s0;
            mosi_s0 <= mosi;
            mosi_s1 <= mosi_s0;
            if (ASYNC) begin
                sclk_d <= sclk_s1;
                cs_d   <= cs_s1;
            end else begin
                sclk_d <= sclk_s0;
                cs_d   <= cs_s0;
            end
        end
    end

    wire sclk_s = ASYNC ? sclk_s1 : sclk_s0;
    wire cs_s   = ASYNC ? cs_s1   : cs_s0;
    wire mosi_s = ASYNC ? mosi_s1 : mosi_s0;

    wire cs_fall =  cs_d & ~cs_s;
    wire cs_rise = ~cs_d &  cs_s;
    wire sclk_ed =  sclk_s ^ sclk_d;

    wire lead_edge   = sclk_ed & (sclk_d == cpol);
    wire trail_edge  = sclk_ed & (sclk_d != cpol);
    wire sample_edge = cpha ? trail_edge : lead_edge;
    wire shift_edge  = cpha ? lead_edge  : trail_edge;

    assign selected = ~cs_s;
    assign miso_oe  = ~cs_s;

    reg [IW-1:0]        bit_cnt;
    reg [IW-1:0]        bits_tot;
    reg [MAX_WIDTH-1:0] tx_sh;
    reg [MAX_WIDTH-1:0] rx_sh;
    reg                 lsb_r;
    reg                 active;
    reg                 word_gap;
    reg                 clk_idle;
    reg                 rx_ready;

    wire [IW-1:0] next_cnt = bit_cnt + 1'b1;
    wire [BW-1:0] bit_sel  = lsb_r ? bit_cnt[BW-1:0] : (bits_tot[BW-1:0] - 1'b1 - bit_cnt[BW-1:0]);

    wire [MAX_WIDTH-1:0] rx_next;
    genvar gi;
    generate
        for (gi = 0; gi < MAX_WIDTH; gi = gi + 1) begin : g_rx
            assign rx_next[gi] = (gi == bit_sel) ? mosi_s : rx_sh[gi];
        end
    endgenerate

    function first_bit;
        input [MAX_WIDTH-1:0] data;
        input [IW-1:0]        tot;
        input                 lsb;
        begin
            if (lsb)
                first_bit = data[0];
            else
                first_bit = data[(tot - 1'b1) % MAX_WIDTH];
        end
    endfunction

    task arm_word;
        begin
            bits_tot <= bits_clamped[IW-1:0];
            tx_sh    <= tx_data;
            rx_sh    <= {MAX_WIDTH{1'b0}};
            bit_cnt  <= {IW{1'b0}};
            lsb_r    <= lsb_first;
            active   <= 1'b1;
            busy     <= 1'b1;
            word_gap <= 1'b0;
            clk_idle <= 1'b0;
            miso     <= cpha ? 1'b0 : first_bit(tx_data, bits_clamped[IW-1:0], lsb_first);
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt      <= {IW{1'b0}};
            bits_tot     <= {{(IW-4){1'b0}}, 4'd8};
            tx_sh        <= {MAX_WIDTH{1'b0}};
            rx_sh        <= {MAX_WIDTH{1'b0}};
            rx_data      <= {MAX_WIDTH{1'b0}};
            lsb_r        <= 1'b0;
            active       <= 1'b0;
            busy         <= 1'b0;
            word_gap     <= 1'b0;
            clk_idle     <= 1'b0;
            rx_ready     <= 1'b0;
            rx_valid     <= 1'b0;
            overrun      <= 1'b0;
            mid_cs_abort <= 1'b0;
            miso         <= 1'b0;
        end else begin
            rx_valid     <= 1'b0;
            mid_cs_abort <= 1'b0;
            if (rx_clear)
                rx_ready <= 1'b0;

            if (cs_fall) begin
                arm_word;
            end else if (active && cs_rise) begin
                if (bit_cnt != {IW{1'b0}})
                    mid_cs_abort <= 1'b1;
                active   <= 1'b0;
                busy     <= 1'b0;
                word_gap <= 1'b0;
                clk_idle <= 1'b0;
                miso     <= 1'b0;
            end else if (active && sclk_ed) begin
                if (shift_edge && word_gap) begin
                    clk_idle <= trail_edge;
                    if (!cpha)
                        miso <= first_bit(tx_sh, bits_tot, lsb_r);
                    else if (lead_edge)
                        miso <= tx_sh[bit_sel];
                end else if (shift_edge && !word_gap) begin
                    // CPHA=0: bit_cnt was already incremented on the leading
                    // sample, so bit_sel is the next bit to drive.
                    // CPHA=1: bit_cnt still points at the bit to present.
                    miso <= tx_sh[bit_sel];
                end
                if (sample_edge) begin
                    word_gap <= 1'b0;
                    rx_sh    <= rx_next;
                    if (bit_cnt == (bits_tot - 1'b1)) begin
                        if (rx_ready && !rx_clear)
                            overrun <= 1'b1;
                        rx_data  <= rx_next;
                        rx_ready <= 1'b1;
                        rx_valid <= 1'b1;
                        bit_cnt  <= {IW{1'b0}};
                        tx_sh    <= tx_data;
                        bits_tot <= bits_clamped[IW-1:0];
                        lsb_r    <= lsb_first;
                        // Keep the last MISO bit stable until SCLK returns to CPOL.
                        word_gap <= 1'b1;
                        clk_idle <= 1'b0;
                        if (cs_s) begin
                            active <= 1'b0;
                            busy   <= 1'b0;
                        end
                    end else begin
                        bit_cnt <= next_cnt;
                    end
                end
            end else if (active && word_gap && !cs_s) begin
                // Between words while CS stays low: take the latest tx_data
                // so the next word can be written after the previous done.
                tx_sh    <= tx_data;
                bits_tot <= bits_clamped[IW-1:0];
                lsb_r    <= lsb_first;
                if (!cpha && clk_idle)
                    miso <= first_bit(tx_data, bits_clamped[IW-1:0], lsb_first);
            end else if (!active && !cs_s) begin
                // CS was already low (tied low after reset). The CS
                // synchroniser comes out of reset as high, so a real
                // falling edge is usually seen. This branch covers the
                // case where that edge was missed.
                arm_word;
            end
        end
    end

endmodule
