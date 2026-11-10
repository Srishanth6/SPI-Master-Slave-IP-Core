// spi_master.v - SPI master
// Author: B. Srishanth Reddy
//
// SCLK frequency = f_clk / (2 * clkdiv), clkdiv >= 1. A value of 0 is treated as 1.
// CPOL is the idle level of SCLK.
// CPHA=0: MOSI is set before the first SCLK edge; data is sampled on the leading edge.
// CPHA=1: MOSI changes on the leading edge; data is sampled on the trailing edge.
// nbits is the word length, 1 to MAX_WIDTH. Data is right-justified.
// lsb_first=0 sends bit nbits-1 first; lsb_first=1 sends bit 0 first.
// start is taken in IDLE, or in WAIT when CS is held low for the next word.
// done is a one-cycle pulse after every word. abort raises CS at once.

`timescale 1ns/1ps
module spi_master #(
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
    input  wire [MAX_WIDTH-1:0]     tx_data,
    output reg  [MAX_WIDTH-1:0]     rx_data,
    output wire                     busy,
    output reg                      done,
    output wire                     tx_ready,
    output reg                      aborted,
    output reg                      sclk,
    output reg                      mosi,
    input  wire                     miso,
    output reg                      cs_n
);

    localparam ST_IDLE  = 3'd0;
    localparam ST_LEAD  = 3'd1;
    localparam ST_XFER  = 3'd2;
    localparam ST_TRAIL = 3'd3;
    localparam ST_WAIT  = 3'd4;
    localparam ST_ABORT = 3'd5;

    localparam IW = $clog2(MAX_WIDTH + 1);
    localparam BW = $clog2(MAX_WIDTH);

    reg [2:0]            st;
    reg [15:0]           hcnt;
    reg [IW-1:0]         bit_cnt;
    reg [IW-1:0]         bits_tot;
    reg [MAX_WIDTH-1:0]  tx_sh;
    reg [MAX_WIDTH-1:0]  rx_sh;
    reg                  cpol_r, cpha_r, lsb_r;
    reg                  sample_half;

    wire [15:0] div_use = (clkdiv == 16'd0) ? 16'd1 : clkdiv;

    wire [5:0] bits_clamped = (nbits == 6'd0) ? 6'd1 :
                              (nbits > MAX_WIDTH[5:0]) ? MAX_WIDTH[5:0] : nbits;

    assign busy     = (st != ST_IDLE);
    assign tx_ready = ((st == ST_IDLE) && enable) || (st == ST_WAIT);

    wire [IW-1:0] next_cnt = bit_cnt + 1'b1;
    wire [BW-1:0] bit_sel  = lsb_r ? bit_cnt[BW-1:0] : (bits_tot[BW-1:0] - 1'b1 - bit_cnt[BW-1:0]);
    wire [BW-1:0] next_sel = lsb_r ? next_cnt[BW-1:0] : (bits_tot[BW-1:0] - 1'b1 - next_cnt[BW-1:0]);

    wire [MAX_WIDTH-1:0] rx_next;

    genvar gi;
    generate
        for (gi = 0; gi < MAX_WIDTH; gi = gi + 1) begin : g_rx
            assign rx_next[gi] = (gi == bit_sel) ? miso : rx_sh[gi];
        end
    endgenerate

    function mosi_first;
        input [MAX_WIDTH-1:0] data;
        input [IW-1:0]        tot;
        input                 lsb;
        begin
            if (lsb)
                mosi_first = data[0];
            else
                mosi_first = data[(tot - 1'b1) % MAX_WIDTH];
        end
    endfunction

    wire mid_word = (st == ST_LEAD) || (st == ST_XFER);
    wire do_abort = mid_word && (abort_req || !enable);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st          <= ST_IDLE;
            hcnt        <= 16'd0;
            bit_cnt     <= {IW{1'b0}};
            bits_tot    <= {{(IW-4){1'b0}}, 4'd8};
            tx_sh       <= {MAX_WIDTH{1'b0}};
            rx_sh       <= {MAX_WIDTH{1'b0}};
            rx_data     <= {MAX_WIDTH{1'b0}};
            cpol_r      <= 1'b0;
            cpha_r      <= 1'b0;
            lsb_r       <= 1'b0;
            sample_half <= 1'b0;
            sclk        <= 1'b0;
            mosi        <= 1'b0;
            cs_n        <= 1'b1;
            done        <= 1'b0;
            aborted     <= 1'b0;
        end else begin
`ifndef INJECT_BUG_DONE
            done <= 1'b0;
`endif

            if (do_abort) begin
                st      <= ST_ABORT;
                hcnt    <= 16'd0;
                aborted <= 1'b1;
                cs_n    <= 1'b1;
                sclk    <= cpol_r;
                mosi    <= 1'b0;
            end else begin
                case (st)
                ST_IDLE: begin
                    cs_n <= 1'b1;
                    sclk <= cpol;
                    mosi <= 1'b0;
                    if (enable && start) begin
                        cpol_r   <= cpol;
                        cpha_r   <= cpha;
                        lsb_r    <= lsb_first;
                        bits_tot <= bits_clamped[IW-1:0];
                        tx_sh    <= tx_data;
                        rx_sh    <= {MAX_WIDTH{1'b0}};
                        bit_cnt  <= {IW{1'b0}};
                        hcnt     <= 16'd0;
                        sclk     <= cpol;
                        cs_n     <= 1'b0;
                        aborted  <= 1'b0;
                        mosi     <= cpha ? 1'b0 : mosi_first(tx_data, bits_clamped[IW-1:0], lsb_first);
                        st       <= ST_LEAD;
                    end
                end

                ST_LEAD: begin
                    if (hcnt == (div_use - 16'd1)) begin
                        hcnt        <= 16'd0;
                        sclk        <= ~sclk;
                        if (cpha_r)
                            mosi    <= tx_sh[bit_sel];
`ifdef INJECT_BUG_SAMPLE
                        sample_half <= cpha_r;
`else
                        sample_half <= ~cpha_r;
`endif
                        st          <= ST_XFER;
                    end else begin
                        hcnt <= hcnt + 16'd1;
                    end
                end

                ST_XFER: begin
                    if (hcnt == (div_use - 16'd1)) begin
                        hcnt <= 16'd0;
                        if (sample_half) begin
                            rx_sh <= rx_next;
                            if (bit_cnt == (bits_tot - 1'b1)) begin
                                rx_data <= rx_next;
                                done    <= 1'b1;
                                if (!cpha_r)
                                    sclk <= ~sclk;
                                st <= ST_TRAIL;
                            end else begin
                                bit_cnt     <= next_cnt;
                                sclk        <= ~sclk;
                                sample_half <= 1'b0;
                                mosi        <= tx_sh[next_sel];
                            end
                        end else begin
                            sclk        <= ~sclk;
                            sample_half <= 1'b1;
                        end
                    end else begin
                        hcnt <= hcnt + 16'd1;
                    end
                end

                ST_TRAIL: begin
                    if (hcnt == (div_use - 16'd1)) begin
                        hcnt <= 16'd0;
                        if (cs_keep && enable) begin
                            if (start) begin
                                tx_sh   <= tx_data;
                                rx_sh   <= {MAX_WIDTH{1'b0}};
                                bit_cnt <= {IW{1'b0}};
                                mosi    <= cpha_r ? 1'b0 : mosi_first(tx_data, bits_tot, lsb_r);
                                sclk    <= cpol_r;
                                st      <= ST_LEAD;
                            end else begin
                                st <= ST_WAIT;
                            end
                        end else begin
                            cs_n <= 1'b1;
                            sclk <= cpol_r;
                            mosi <= 1'b0;
                            st   <= ST_IDLE;
                        end
                    end else begin
                        hcnt <= hcnt + 16'd1;
                    end
                end

                ST_WAIT: begin
                    sclk <= cpol_r;
                    if (!cs_keep || !enable) begin
                        cs_n <= 1'b1;
                        mosi <= 1'b0;
                        st   <= ST_IDLE;
                    end else if (start) begin
                        tx_sh   <= tx_data;
                        rx_sh   <= {MAX_WIDTH{1'b0}};
                        bit_cnt <= {IW{1'b0}};
                        hcnt    <= 16'd0;
                        mosi    <= cpha_r ? 1'b0 : mosi_first(tx_data, bits_tot, lsb_r);
                        sclk    <= cpol_r;
                        st      <= ST_LEAD;
                    end
                end

                ST_ABORT: begin
                    cs_n <= 1'b1;
                    sclk <= cpol_r;
                    mosi <= 1'b0;
                    st   <= ST_IDLE;
                end

                default: st <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
