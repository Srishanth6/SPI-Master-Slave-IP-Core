//      // verilator_coverage annotation
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
 000032     input  wire [MAX_WIDTH-1:0]     tx_data,
 000034     output reg  [MAX_WIDTH-1:0]     rx_data,
 000092     output wire                     busy,
 000111     output reg                      done,
 000105     output wire                     tx_ready,
%000000     output reg                      aborted,
 002271     output reg                      sclk,
 000573     output reg                      mosi,
 000653     input  wire                     miso,
 000093     output reg                      cs_n
        );
        
            localparam ST_IDLE  = 3'd0;
            localparam ST_LEAD  = 3'd1;
            localparam ST_XFER  = 3'd2;
            localparam ST_TRAIL = 3'd3;
            localparam ST_WAIT  = 3'd4;
            localparam ST_ABORT = 3'd5;
        
            localparam IW = $clog2(MAX_WIDTH + 1);
            localparam BW = $clog2(MAX_WIDTH);
        
 000215     reg [2:0]            st;
~007996     reg [15:0]           hcnt;
~001124     reg [IW-1:0]         bit_cnt;
~000022     reg [IW-1:0]         bits_tot;
 000032     reg [MAX_WIDTH-1:0]  tx_sh;
 000060     reg [MAX_WIDTH-1:0]  rx_sh;
 000023     reg                  cpol_r, cpha_r, lsb_r;
 002196     reg                  sample_half;
        
~092244     wire [15:0] div_use = (clkdiv == 16'd0) ? 16'd1 : clkdiv;
        
~092244     wire [5:0] bits_clamped = (nbits == 6'd0) ? 6'd1 :
~092244                               (nbits > MAX_WIDTH[5:0]) ? MAX_WIDTH[5:0] : nbits;
        
            assign busy     = (st != ST_IDLE);
~091215     assign tx_ready = ((st == ST_IDLE) && enable) || (st == ST_WAIT);
        
 001124     wire [IW-1:0] next_cnt = bit_cnt + 1'b1;
 011179     wire [BW-1:0] bit_sel  = lsb_r ? bit_cnt[BW-1:0] : (bits_tot[BW-1:0] - 1'b1 - bit_cnt[BW-1:0]);
 011179     wire [BW-1:0] next_sel = lsb_r ? next_cnt[BW-1:0] : (bits_tot[BW-1:0] - 1'b1 - next_cnt[BW-1:0]);
        
 000115     wire [MAX_WIDTH-1:0] rx_next;
        
            genvar gi;
            generate
 571950         for (gi = 0; gi < MAX_WIDTH; gi = gi + 1) begin : g_rx
 571950             assign rx_next[gi] = (gi == bit_sel) ? miso : rx_sh[gi];
                end
            endgenerate
        
 000053     function mosi_first;
                input [MAX_WIDTH-1:0] data;
                input [IW-1:0]        tot;
                input                 lsb;
 000053         begin
 000028             if (lsb)
 000025                 mosi_first = data[0];
                    else
 000028                 mosi_first = data[(tot - 1'b1) % MAX_WIDTH];
                end
            endfunction
        
 017407     wire mid_word = (st == ST_LEAD) || (st == ST_XFER);
~092244     wire do_abort = mid_word && (abort_req || !enable);
        
 018449     always @(posedge clk or negedge rst_n) begin
~018446         if (!rst_n) begin
%000003             st          <= ST_IDLE;
%000003             hcnt        <= 16'd0;
%000003             bit_cnt     <= {IW{1'b0}};
%000003             bits_tot    <= {{(IW-4){1'b0}}, 4'd8};
%000003             tx_sh       <= {MAX_WIDTH{1'b0}};
%000003             rx_sh       <= {MAX_WIDTH{1'b0}};
%000003             rx_data     <= {MAX_WIDTH{1'b0}};
%000003             cpol_r      <= 1'b0;
%000003             cpha_r      <= 1'b0;
%000003             lsb_r       <= 1'b0;
%000003             sample_half <= 1'b0;
%000003             sclk        <= 1'b0;
%000003             mosi        <= 1'b0;
%000003             cs_n        <= 1'b1;
%000003             done        <= 1'b0;
%000003             aborted     <= 1'b0;
 018446         end else begin
        `ifndef INJECT_BUG_DONE
 018446             done <= 1'b0;
        `endif
        
~018446             if (do_abort) begin
%000000                 st      <= ST_ABORT;
%000000                 hcnt    <= 16'd0;
%000000                 aborted <= 1'b1;
%000000                 cs_n    <= 1'b1;
%000000                 sclk    <= cpol_r;
%000000                 mosi    <= 1'b0;
 018446             end else begin
 018446                 case (st)
 000191                 ST_IDLE: begin
 000191                     cs_n <= 1'b1;
 000191                     sclk <= cpol;
 000191                     mosi <= 1'b0;
~000099                     if (enable && start) begin
 000092                         cpol_r   <= cpol;
 000092                         cpha_r   <= cpha;
 000092                         lsb_r    <= lsb_first;
 000092                         bits_tot <= bits_clamped[IW-1:0];
 000092                         tx_sh    <= tx_data;
 000092                         rx_sh    <= {MAX_WIDTH{1'b0}};
 000092                         bit_cnt  <= {IW{1'b0}};
 000092                         hcnt     <= 16'd0;
 000092                         sclk     <= cpol;
 000092                         cs_n     <= 1'b0;
 000092                         aborted  <= 1'b0;
 000092                         mosi     <= cpha ? 1'b0 : mosi_first(tx_data, bits_clamped[IW-1:0], lsb_first);
 000092                         st       <= ST_LEAD;
                            end
                        end
        
 000418                 ST_LEAD: begin
 000307                     if (hcnt == (div_use - 16'd1)) begin
 000111                         hcnt        <= 16'd0;
 000111                         sclk        <= ~sclk;
 000058                         if (cpha_r)
 000058                             mosi    <= tx_sh[bit_sel];
        `ifdef INJECT_BUG_SAMPLE
                                sample_half <= cpha_r;
        `else
 000111                         sample_half <= ~cpha_r;
        `endif
 000111                         st          <= ST_XFER;
 000307                     end else begin
 000307                         hcnt <= hcnt + 16'd1;
                            end
                        end
        
 017407                 ST_XFER: begin
 012964                     if (hcnt == (div_use - 16'd1)) begin
 004443                         hcnt <= 16'd0;
 002248                         if (sample_half) begin
 002248                             rx_sh <= rx_next;
 002137                             if (bit_cnt == (bits_tot - 1'b1)) begin
 000111                                 rx_data <= rx_next;
 000111                                 done    <= 1'b1;
 000058                                 if (!cpha_r)
 000053                                     sclk <= ~sclk;
 000111                                 st <= ST_TRAIL;
 002137                             end else begin
 002137                                 bit_cnt     <= next_cnt;
 002137                                 sclk        <= ~sclk;
 002137                                 sample_half <= 1'b0;
 002137                                 mosi        <= tx_sh[next_sel];
                                    end
 002195                         end else begin
 002195                             sclk        <= ~sclk;
 002195                             sample_half <= 1'b1;
                                end
 012964                     end else begin
 012964                         hcnt <= hcnt + 16'd1;
                            end
                        end
        
 000418                 ST_TRAIL: begin
 000307                     if (hcnt == (div_use - 16'd1)) begin
 000111                         hcnt <= 16'd0;
~000092                         if (cs_keep && enable) begin
~000012                             if (start) begin
%000007                                 tx_sh   <= tx_data;
%000007                                 rx_sh   <= {MAX_WIDTH{1'b0}};
%000007                                 bit_cnt <= {IW{1'b0}};
%000007                                 mosi    <= cpha_r ? 1'b0 : mosi_first(tx_data, bits_tot, lsb_r);
%000007                                 sclk    <= cpol_r;
%000007                                 st      <= ST_LEAD;
 000012                             end else begin
 000012                                 st <= ST_WAIT;
                                    end
 000092                         end else begin
 000092                             cs_n <= 1'b1;
 000092                             sclk <= cpol_r;
 000092                             mosi <= 1'b0;
 000092                             st   <= ST_IDLE;
                                end
 000307                     end else begin
 000307                         hcnt <= hcnt + 16'd1;
                            end
                        end
        
 000012                 ST_WAIT: begin
 000012                     sclk <= cpol_r;
~000012                     if (!cs_keep || !enable) begin
%000000                         cs_n <= 1'b1;
%000000                         mosi <= 1'b0;
%000000                         st   <= ST_IDLE;
~000012                     end else if (start) begin
 000012                         tx_sh   <= tx_data;
 000012                         rx_sh   <= {MAX_WIDTH{1'b0}};
 000012                         bit_cnt <= {IW{1'b0}};
 000012                         hcnt    <= 16'd0;
~000012                         mosi    <= cpha_r ? 1'b0 : mosi_first(tx_data, bits_tot, lsb_r);
 000012                         sclk    <= cpol_r;
 000012                         st      <= ST_LEAD;
                            end
                        end
        
%000000                 ST_ABORT: begin
%000000                     cs_n <= 1'b1;
%000000                     sclk <= cpol_r;
%000000                     mosi <= 1'b0;
%000000                     st   <= ST_IDLE;
                        end
        
%000000                 default: st <= ST_IDLE;
                        endcase
                    end
                end
            end
        
        endmodule
        
