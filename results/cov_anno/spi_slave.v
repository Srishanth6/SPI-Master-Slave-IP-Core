//      // verilator_coverage annotation
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
 018449     input  wire                     clk,
%000001     input  wire                     rst_n,
 000023     input  wire                     cpol,
 000019     input  wire                     cpha,
 000020     input  wire                     lsb_first,
~000022     input  wire [5:0]               nbits,
 000034     input  wire [MAX_WIDTH-1:0]     tx_data,
 000031     output reg  [MAX_WIDTH-1:0]     rx_data,
 000111     output reg                      rx_valid,
 000093     output wire                     selected,
 000092     output reg                      busy,
%000000     output reg                      overrun,
%000000     output reg                      mid_cs_abort,
 000111     input  wire                     rx_clear,
 002271     input  wire                     sclk,
 000573     input  wire                     mosi,
 000093     input  wire                     cs_n,
 000604     output reg                      miso,
 000093     output wire                     miso_oe
        );
        
            localparam IW = $clog2(MAX_WIDTH + 1);
            localparam BW = $clog2(MAX_WIDTH);
        
~092244     wire [5:0] bits_clamped = (nbits == 6'd0) ? 6'd1 :
~092244                               (nbits > MAX_WIDTH[5:0]) ? MAX_WIDTH[5:0] : nbits;
        
 002271     reg sclk_s0, sclk_s1, cs_s0, cs_s1, mosi_s0, mosi_s1;
 002271     reg sclk_d, cs_d;
        
 018449     always @(posedge clk or negedge rst_n) begin
~018446         if (!rst_n) begin
%000003             sclk_s0 <= 1'b0;
%000003             sclk_s1 <= 1'b0;
%000003             cs_s0   <= 1'b1;
%000003             cs_s1   <= 1'b1;
%000003             mosi_s0 <= 1'b0;
%000003             mosi_s1 <= 1'b0;
%000003             sclk_d  <= 1'b0;
%000003             cs_d    <= 1'b1;
 018446         end else begin
 018446             sclk_s0 <= sclk;
 018446             sclk_s1 <= sclk_s0;
 018446             cs_s0   <= cs_n;
 018446             cs_s1   <= cs_s0;
 018446             mosi_s0 <= mosi;
 018446             mosi_s1 <= mosi_s0;
~018446             if (ASYNC) begin
%000000                 sclk_d <= sclk_s1;
%000000                 cs_d   <= cs_s1;
 018446             end else begin
 018446                 sclk_d <= sclk_s0;
 018446                 cs_d   <= cs_s0;
                    end
                end
            end
        
~002271     wire sclk_s = ASYNC ? sclk_s1 : sclk_s0;
~000093     wire cs_s   = ASYNC ? cs_s1   : cs_s0;
~000573     wire mosi_s = ASYNC ? mosi_s1 : mosi_s0;
        
 018256     wire cs_fall =  cs_d & ~cs_s;
 018256     wire cs_rise = ~cs_d &  cs_s;
 007020     wire sclk_ed =  sclk_s ^ sclk_d;
        
 069539     wire lead_edge   = sclk_ed & (sclk_d == cpol);
 069539     wire trail_edge  = sclk_ed & (sclk_d != cpol);
 053750     wire sample_edge = cpha ? trail_edge : lead_edge;
 053750     wire shift_edge  = cpha ? lead_edge  : trail_edge;
        
 018256     assign selected = ~cs_s;
 018256     assign miso_oe  = ~cs_s;
        
~001124     reg [IW-1:0]        bit_cnt;
~000022     reg [IW-1:0]        bits_tot;
 000034     reg [MAX_WIDTH-1:0] tx_sh;
 000057     reg [MAX_WIDTH-1:0] rx_sh;
 000020     reg                 lsb_r;
 000092     reg                 active;
 000111     reg                 word_gap;
 000053     reg                 clk_idle;
 000111     reg                 rx_ready;
        
 001125     wire [IW-1:0] next_cnt = bit_cnt + 1'b1;
 011179     wire [BW-1:0] bit_sel  = lsb_r ? bit_cnt[BW-1:0] : (bits_tot[BW-1:0] - 1'b1 - bit_cnt[BW-1:0]);
        
 000086     wire [MAX_WIDTH-1:0] rx_next;
            genvar gi;
            generate
 571950         for (gi = 0; gi < MAX_WIDTH; gi = gi + 1) begin : g_rx
 571950             assign rx_next[gi] = (gi == bit_sel) ? mosi_s : rx_sh[gi];
                end
            endgenerate
        
 000249     function first_bit;
                input [MAX_WIDTH-1:0] data;
                input [IW-1:0]        tot;
                input                 lsb;
 000249         begin
 000143             if (lsb)
 000106                 first_bit = data[0];
                    else
 000143                 first_bit = data[(tot - 1'b1) % MAX_WIDTH];
                end
            endfunction
        
 000092     task arm_word;
 000092         begin
 000092             bits_tot <= bits_clamped[IW-1:0];
 000092             tx_sh    <= tx_data;
 000092             rx_sh    <= {MAX_WIDTH{1'b0}};
 000092             bit_cnt  <= {IW{1'b0}};
 000092             lsb_r    <= lsb_first;
 000092             active   <= 1'b1;
 000092             busy     <= 1'b1;
 000092             word_gap <= 1'b0;
 000092             clk_idle <= 1'b0;
 000092             miso     <= cpha ? 1'b0 : first_bit(tx_data, bits_clamped[IW-1:0], lsb_first);
                end
            endtask
        
 018449     always @(posedge clk or negedge rst_n) begin
~018446         if (!rst_n) begin
%000003             bit_cnt      <= {IW{1'b0}};
%000003             bits_tot     <= {{(IW-4){1'b0}}, 4'd8};
%000003             tx_sh        <= {MAX_WIDTH{1'b0}};
%000003             rx_sh        <= {MAX_WIDTH{1'b0}};
%000003             rx_data      <= {MAX_WIDTH{1'b0}};
%000003             lsb_r        <= 1'b0;
%000003             active       <= 1'b0;
%000003             busy         <= 1'b0;
%000003             word_gap     <= 1'b0;
%000003             clk_idle     <= 1'b0;
%000003             rx_ready     <= 1'b0;
%000003             rx_valid     <= 1'b0;
%000003             overrun      <= 1'b0;
%000003             mid_cs_abort <= 1'b0;
%000003             miso         <= 1'b0;
 018446         end else begin
 018446             rx_valid     <= 1'b0;
 018446             mid_cs_abort <= 1'b0;
 018335             if (rx_clear)
 000111                 rx_ready <= 1'b0;
        
 000092             if (cs_fall) begin
 000092                 arm_word;
 018262             end else if (active && cs_rise) begin
~000092                 if (bit_cnt != {IW{1'b0}})
%000000                     mid_cs_abort <= 1'b1;
 000092                 active   <= 1'b0;
 000092                 busy     <= 1'b0;
 000092                 word_gap <= 1'b0;
 000092                 clk_idle <= 1'b0;
 000092                 miso     <= 1'b0;
 013721             end else if (active && sclk_ed) begin
 004416                 if (shift_edge && word_gap) begin
 000061                     clk_idle <= trail_edge;
~000053                     if (!cpha)
 000053                         miso <= first_bit(tx_sh, bits_tot, lsb_r);
%000008                     else if (lead_edge)
%000008                         miso <= tx_sh[bit_sel];
 002248                 end else if (shift_edge && !word_gap) begin
                            // CPHA=0: bit_cnt was already incremented on the leading
                            // sample, so bit_sel is the next bit to drive.
                            // CPHA=1: bit_cnt still points at the bit to present.
 002187                     miso <= tx_sh[bit_sel];
                        end
 002248                 if (sample_edge) begin
 002248                     word_gap <= 1'b0;
 002248                     rx_sh    <= rx_next;
 002137                     if (bit_cnt == (bits_tot - 1'b1)) begin
~000111                         if (rx_ready && !rx_clear)
%000000                             overrun <= 1'b1;
 000111                         rx_data  <= rx_next;
 000111                         rx_ready <= 1'b1;
 000111                         rx_valid <= 1'b1;
 000111                         bit_cnt  <= {IW{1'b0}};
 000111                         tx_sh    <= tx_data;
 000111                         bits_tot <= bits_clamped[IW-1:0];
 000111                         lsb_r    <= lsb_first;
                                // Keep the last MISO bit stable until SCLK returns to CPOL.
 000111                         word_gap <= 1'b1;
 000111                         clk_idle <= 1'b0;
~000111                         if (cs_s) begin
%000000                             active <= 1'b0;
%000000                             busy   <= 1'b0;
                                end
 002137                     end else begin
 002137                         bit_cnt <= next_cnt;
                            end
                        end
 013029             end else if (active && word_gap && !cs_s) begin
                        // Between words while CS stays low: take the latest tx_data
                        // so the next word can be written after the previous done.
 000737                 tx_sh    <= tx_data;
 000737                 bits_tot <= bits_clamped[IW-1:0];
 000737                 lsb_r    <= lsb_first;
 000583                 if (!cpha && clk_idle)
 000154                     miso <= first_bit(tx_data, bits_clamped[IW-1:0], lsb_first);
~013029             end else if (!active && !cs_s) begin
                        // CS was already low (tied low after reset). The CS
                        // synchroniser comes out of reset as high, so a real
                        // falling edge is usually seen. This branch covers the
                        // case where that edge was missed.
%000000                 arm_word;
                    end
                end
            end
        
        endmodule
        
