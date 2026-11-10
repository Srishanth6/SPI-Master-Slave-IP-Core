// spi_icebreaker.v - on-chip master/slave loopback for the iCEBreaker
// Author: B. Srishanth Reddy
//
// After reset the core sends four 8-bit words in SPI mode 0. The green LED
// lights if every word matches; the red LED lights if one fails. The SPI
// pins are also brought out to PMOD 1A.

`timescale 1ns/1ps
module spi_icebreaker (
    input  wire clk,
    input  wire rst_n,
    output wire led_g,
    output wire led_r,
    output wire sclk,
    output wire mosi,
    output wire miso,
    output wire cs_n
);

    localparam [31:0] TX0 = 32'hA5, RX0 = 32'h5A;
    localparam [31:0] TX1 = 32'h3C, RX1 = 32'hC3;
    localparam [31:0] TX2 = 32'h12, RX2 = 32'h34;
    localparam [31:0] TX3 = 32'h77, RX3 = 32'h88;

    wire        rst_n_sync;
    reg  [2:0]  rst_s;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) rst_s <= 3'b000;
        else        rst_s <= {rst_s[1:0], 1'b1};
    assign rst_n_sync = rst_s[2];

    reg         enable, start;
    reg  [1:0]  idx;
    reg  [31:0] m_tx, s_tx;
    wire [31:0] m_rx, s_rx;
    wire        busy, done, tx_ready;
    reg         pass, fail, started;
    reg  [1:0]  st;

    localparam S_IDLE=2'd0, S_GO=2'd1, S_WAIT=2'd2, S_DONE=2'd3;

    always @* begin
        case (idx)
        2'd0: begin m_tx = TX0; s_tx = RX0; end
        2'd1: begin m_tx = TX1; s_tx = RX1; end
        2'd2: begin m_tx = TX2; s_tx = RX2; end
        default: begin m_tx = TX3; s_tx = RX3; end
        endcase
    end

    always @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            enable  <= 1'b0;
            start   <= 1'b0;
            idx     <= 2'd0;
            pass    <= 1'b0;
            fail    <= 1'b0;
            started <= 1'b0;
            st      <= S_IDLE;
        end else begin
            start <= 1'b0;
            case (st)
            S_IDLE: begin
                enable <= 1'b1;
                if (tx_ready && !started) begin
                    start   <= 1'b1;
                    started <= 1'b1;
                    st      <= S_WAIT;
                end
            end
            S_WAIT: begin
                if (done) begin
                    if (m_rx[7:0] != s_tx[7:0] || s_rx[7:0] != m_tx[7:0])
                        fail <= 1'b1;
                    if (idx == 2'd3)
                        st <= S_DONE;
                    else begin
                        idx     <= idx + 2'd1;
                        started <= 1'b0;
                        st      <= S_IDLE;
                    end
                end
            end
            S_DONE: begin
                if (!fail)
                    pass <= 1'b1;
            end
            default: st <= S_DONE;
            endcase
        end
    end

    assign led_g = pass;
    assign led_r = fail;

    spi_loopback #(.MAX_WIDTH(32)) u_lp (
        .clk(clk), .rst_n(rst_n_sync),
        .enable(enable), .clkdiv(16'd4),
        .cpol(1'b0), .cpha(1'b0), .lsb_first(1'b0), .nbits(6'd8),
        .start(start), .cs_keep(1'b0), .abort_req(1'b0),
        .m_tx(m_tx), .m_rx(m_rx), .s_tx(s_tx), .s_rx(s_rx),
        .busy(busy), .done(done), .tx_ready(tx_ready), .aborted(),
        .s_rx_valid(), .s_selected(), .s_overrun(), .s_mid_cs_abort(),
        .s_rx_clear(1'b1),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

endmodule
