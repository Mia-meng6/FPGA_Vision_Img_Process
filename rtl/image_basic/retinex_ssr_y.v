// =============================================================================
// retinex_ssr_y.v 
// =============================================================================
`timescale 1ns / 1ps

module retinex_ssr_y #(
    parameter IMG_WIDTH = 640
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_vsync,
    input  wire        i_hsync,
    input  wire        i_de,
    input  wire [7:0]  i_y_data,
    input  wire [7:0]  i_cb_data,
    input  wire [7:0]  i_cr_data,

    output wire        o_vsync,
    output wire        o_hsync,
    output wire        o_de,
    output wire [7:0]  o_y_data,
    output wire [7:0]  o_cb_data,
    output wire [7:0]  o_cr_data
);

localparam PIPE_DELAY = 5;

// =========================================================================
// Stage A: Line Buffers for Y, Cb, and Cr
// =========================================================================
wire [7:0] y_row1_out, y_row0_out;
wire [7:0] cb_row1_out, cr_row1_out;

Line_Shift_RAM_8Bit #(.RAM_DEPTH(IMG_WIDTH)) u_lsr_y0 (
    .clock   (clk), .clken   (i_de), .shiftin (i_y_data), .shiftout(y_row1_out)
);
Line_Shift_RAM_8Bit #(.RAM_DEPTH(IMG_WIDTH)) u_lsr_y1 (
    .clock   (clk), .clken   (i_de), .shiftin (y_row1_out), .shiftout(y_row0_out)
);

//色度通道的行缓存
Line_Shift_RAM_8Bit #(.RAM_DEPTH(IMG_WIDTH)) u_lsr_cb (
    .clock   (clk), .clken   (i_de), .shiftin (i_cb_data), .shiftout(cb_row1_out)
);
Line_Shift_RAM_8Bit #(.RAM_DEPTH(IMG_WIDTH)) u_lsr_cr (
    .clock   (clk), .clken   (i_de), .shiftin (i_cr_data), .shiftout(cr_row1_out)
);

// 横向滑窗
reg [7:0] p11, p12, p13;
reg [7:0] p21, p22, p23;
reg [7:0] p31, p32, p33;

reg [7:0] cb_p23, cb_p22;
reg [7:0] cr_p23, cr_p22;

always @(posedge clk) begin
    if (i_de) begin
        p13 <= y_row0_out; p12 <= p13; p11 <= p12;
        p23 <= y_row1_out; p22 <= p23; p21 <= p22;
        p33 <= i_y_data;   p32 <= p33; p31 <= p32;

        cb_p23 <= cb_row1_out; cb_p22 <= cb_p23;
        cr_p23 <= cr_row1_out; cr_p22 <= cr_p23;
    end
end

// =========================================================================
// Stage B: 3x3 求和 + 1/9 近似
// =========================================================================
reg [7:0] i_blur;
reg [7:0] orig_y_pipe;
reg [7:0] cb_pipe_b, cr_pipe_b;

reg [1:0] de_pipe_ab;
always @(posedge clk) de_pipe_ab <= {de_pipe_ab[0], i_de};
wire de_stageA_valid = de_pipe_ab[1];

always @(posedge clk) begin
    if (de_stageA_valid) begin
        i_blur     <= ((p11 + p12 + p13 +
                        p21 + p22 + p23 +
                        p31 + p32 + p33) * 16'd28) >> 8;
        orig_y_pipe <= p22;
        cb_pipe_b   <= cb_p22; 
        cr_pipe_b   <= cr_p22;
    end
end

// =========================================================================
// Stage C: 对数查表
// =========================================================================
reg [9:0] log_rom [0:255];
initial begin
    $readmemh("log_lut.txt", log_rom);
end

wire [9:0] log_orig_comb = log_rom[orig_y_pipe];
wire [9:0] log_blur_comb = log_rom[i_blur];

reg [9:0] log_orig_r, log_blur_r;
reg [7:0] cb_pipe_c, cr_pipe_c;

always @(posedge clk) begin
    log_orig_r <= log_orig_comb;
    log_blur_r <= log_blur_comb;
    cb_pipe_c  <= cb_pipe_b;
    cr_pipe_c  <= cr_pipe_b;
end

// =========================================================================
// Stage D: 差分 + 对比度拉伸 + 饱和截断
// =========================================================================
wire signed [11:0] diff_cal   = $signed({2'b00, log_orig_r}) - $signed({2'b00, log_blur_r});
wire signed [14:0] diff_amp   = diff_cal <<< 2;

reg [7:0] final_y;
reg [7:0] cb_pipe_d, cr_pipe_d;

always @(posedge clk) begin
    if      (diff_amp < 0)         final_y <= 8'd0;
    else if (diff_amp > 15'sd255)  final_y <= 8'd255;
    else                           final_y <= diff_amp[7:0];

    cb_pipe_d <= cb_pipe_c;
    cr_pipe_d <= cr_pipe_c;
end

// =========================================================================
// 控制信号延迟对齐 (5 拍)
// =========================================================================
reg [PIPE_DELAY-1:0] vsync_d, hsync_d, de_d;
always @(posedge clk) begin
    vsync_d <= {vsync_d[PIPE_DELAY-2:0], i_vsync};
    hsync_d <= {hsync_d[PIPE_DELAY-2:0], i_hsync};
    de_d    <= {de_d[PIPE_DELAY-2:0],    i_de};
end

assign o_vsync   = vsync_d[PIPE_DELAY-1];
assign o_hsync   = hsync_d[PIPE_DELAY-1];
assign o_de      = de_d[PIPE_DELAY-1];
assign o_y_data  = final_y;
assign o_cb_data = cb_pipe_d;
assign o_cr_data = cr_pipe_d;

endmodule