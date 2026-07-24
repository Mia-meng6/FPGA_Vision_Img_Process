`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 子模块：CAP_Y_Dehaze（仅对 Y 通道做 CAP 去雾，精确 4 拍流水）
// -----------------------------------------------------------------------------
module CAP_Y_Dehaze #(
    parameter [10:0] IMG_HDISP = 11'd640,
    parameter [10:0] IMG_VDISP = 11'd480
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        srst,
    input  wire        i_vsync,
    input  wire        i_hsync,
    input  wire        i_de,
    input  wire [7:0]  i_y,
    output wire        o_vsync,
    output wire        o_hsync,
    output wire        o_de,
    output wire [7:0]  o_y
);
//常数
localparam [7:0]  THETA0_Q0 = 8'd31;
localparam [8:0]  THETA1_Q8 = 9'd246;
localparam [15:0] INV_T_MAX = 16'd10240;
localparam [15:0] INV_T_MIN = 16'd1024;
// TOP_COUNT 已随大气光估算方式改变而废弃

//动态大气光：帧均值法
reg [26:0] y_sum;   // 防溢出
reg [17:0] y_cnt;   
reg [7:0]  A_y;

// 帧消隐边沿检测
reg vsync_d1;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) vsync_d1 <= 1'b1;
    else        vsync_d1 <= i_vsync;
end
wire vsync_fall = vsync_d1 & ~i_vsync;  // vsync 下降沿

// A_y 低通滤波
reg [7:0] A_y_raw;   // 本帧计算出的原始大气光值

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        y_sum<=27'd0; y_cnt<=18'd0; A_y<=8'd150; A_y_raw<=8'd150;
    end else if (srst) begin
        y_sum<=27'd0; y_cnt<=18'd0; A_y<=8'd150; A_y_raw<=8'd150;
    end else if (vsync_fall) begin
        if (y_cnt > 0) begin : upd
            reg [8:0] a_raw;
            reg [8:0] a_clamp;
            reg signed [9:0] a_delta;
            a_raw  = y_sum[26:18];
            if      (a_raw > 8'd210) a_clamp = 9'd210;
            else if (a_raw < 8'd120) a_clamp = 9'd120;
            else                      a_clamp = {1'b0, a_raw};
            A_y_raw <= a_clamp[7:0];
            a_delta = $signed({2'b00, a_clamp}) - $signed({2'b00, A_y});
            if (a_delta == 0) begin
                A_y <= A_y;  
            end else if ((a_delta >>> 3) == 0) begin
                A_y <= (a_delta > 0) ? (A_y + 8'd1) : (A_y - 8'd1);
            end else begin
                A_y <= $signed({2'b00, A_y}) + (a_delta >>> 3);
            end
        end
        y_sum <= 27'd0;
        y_cnt <= 18'd0;
    end else if (i_de) begin
        y_sum <= y_sum + {19'd0, i_y};
        if (y_cnt < 18'd262143) y_cnt <= y_cnt + 18'd1;
    end
end

// Stage 1：数据采样
reg [7:0] s1_y, s1_A;
reg       s1_vsync, s1_hsync, s1_de;
always @(posedge clk) begin
    s1_y     <= i_y;
    s1_A     <= A_y;
    s1_vsync <= i_vsync;
    s1_hsync <= i_hsync;
    s1_de    <= i_de;
end

// 同步 ROM 潜伏期
reg [7:0] s1_y_d, s1_A_d;
reg       s1_vsync_d, s1_hsync_d, s1_de_d;
always @(posedge clk) begin
    s1_y_d     <= s1_y;
    s1_A_d     <= s1_A;
    s1_vsync_d <= s1_vsync;
    s1_hsync_d <= s1_hsync;
    s1_de_d    <= s1_de;
end

// Stage 2：景深 d = θ₀ + θ₁·(Y-16)
wire [7:0]  y_sub16      = (s1_y > 8'd16) ? (s1_y - 8'd16) : 8'd0;
wire [15:0] theta1_y_q8  = THETA1_Q8 * y_sub16;
wire [8:0]  theta1_y_q0  = theta1_y_q8[15:8];
wire [8:0]  d_raw9        = THETA0_Q0 + theta1_y_q0;
wire [7:0]  d_index       = d_raw9[8] ? 8'd255 : d_raw9[7:0];

wire [15:0] inv_t_rom_data;
d_inv_t_rom u_d_inv_y (
    .clock   (clk),
    .address ({1'b0, d_index}),  
    .data    (16'd0),            
    .wren    (1'b0),            
    .q       (inv_t_rom_data)
);

reg [7:0]  s2_y, s2_A;
reg [15:0] s2_inv_t;
reg        s2_vsync, s2_hsync, s2_de;
always @(posedge clk) begin
    s2_y     <= s1_y_d;    
    s2_A     <= s1_A_d;
    s2_vsync <= s1_vsync_d;
    s2_hsync <= s1_hsync_d;
    s2_de    <= s1_de_d;
    s2_inv_t <= (inv_t_rom_data > INV_T_MAX) ? INV_T_MAX :
                (inv_t_rom_data < INV_T_MIN) ? INV_T_MIN : inv_t_rom_data;
end

// Stage 3： J_y = (Y − A) × inv_t >> 10 + A
wire signed [9:0]  diff_y  = $signed({1'b0, s2_y}) - $signed({1'b0, s2_A});
(* multstyle = "dsp" *)
wire signed [25:0] prod_y  = diff_y * $signed({1'b0, s2_inv_t});

reg [7:0] out_y_r;
reg       s3_vsync, s3_hsync, s3_de;
always @(posedge clk) begin
    s3_vsync <= s2_vsync;
    s3_hsync <= s2_hsync; s3_de <= s2_de;
    begin : cy
        reg signed [16:0] jy;
        reg [9:0] jy_gain;   
        jy = $signed({9'd0, s2_A}) + (prod_y >>> 10);
        if      (jy < 0)   jy_gain = 10'd0;
        else if (jy > 255) jy_gain = 10'd255;
        else                jy_gain = {2'b00, jy[7:0]};
        jy_gain = jy_gain + (jy_gain >> 2);
        out_y_r <= (jy_gain > 10'd255) ? 8'd255 : jy_gain[7:0];
    end
end

assign o_vsync = s3_vsync;
assign o_hsync = s3_hsync;
assign o_de    = s3_de;
assign o_y     = out_y_r;
endmodule


// -----------------------------------------------------------------------------
// 顶层：Dehaze_YCbCr_Top (Retinex )
// -----------------------------------------------------------------------------
module Dehaze_YCbCr_Top #(
    parameter [10:0] IMG_HDISP = 11'd640,
    parameter [10:0] IMG_VDISP = 11'd480
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        srst,
    input  wire        in_vsync,
    input  wire        in_hsync,
    input  wire        in_de,
    input  wire [15:0] in_rgb565,
    output wire        out_vsync,
    output wire        out_hsync,
    output wire        out_de,
    output wire [15:0] out_rgb565
);

// Step 0：位扩展
wire [7:0] raw_r = {in_rgb565[15:11], in_rgb565[15:13]};
wire [7:0] raw_g = {in_rgb565[10:5],  in_rgb565[10:9]};
wire [7:0] raw_b = {in_rgb565[4:0],   in_rgb565[4:2]};

// Step 1：RGB → YCbCr 
wire [7:0] yuv_y, yuv_cb, yuv_cr;
wire       yuv_h, yuv_v, yuv_de;
rgb_to_ycbcr u_rgb2yuv (
    .clk(clk), .i_r_8b(raw_r), .i_g_8b(raw_g), .i_b_8b(raw_b),
    .i_h_sync(in_hsync), .i_v_sync(in_vsync), .i_data_en(in_de),
    .o_y_8b(yuv_y), .o_cb_8b(yuv_cb), .o_cr_8b(yuv_cr),
    .o_h_sync(yuv_h), .o_v_sync(yuv_v), .o_data_en(yuv_de)
);

// Step 2：CAP 去雾 
wire [7:0] dh_y;
wire       dh_v, dh_h, dh_de;
CAP_Y_Dehaze #(.IMG_HDISP(IMG_HDISP), .IMG_VDISP(IMG_VDISP)) u_cap_y (
    .clk(clk), .rst_n(rst_n), .srst(srst),
    .i_vsync(yuv_v), .i_hsync(yuv_h), .i_de(yuv_de), .i_y(yuv_y),
    .o_vsync(dh_v), .o_hsync(dh_h), .o_de(dh_de), .o_y(dh_y)
);

// 色度对齐 CAP 去雾 
reg [7:0] cb_d1[0:3], cr_d1[0:3];
integer i;
always @(posedge clk) begin
    cb_d1[0] <= yuv_cb; cr_d1[0] <= yuv_cr;
    for(i=1; i<4; i=i+1) begin
        cb_d1[i] <= cb_d1[i-1]; cr_d1[i] <= cr_d1[i-1];
    end
end

// Step 3
reg [7:0] y_hold[0:4], cb_hold[0:4], cr_hold[0:4];
reg [4:0] v_hold, h_hold, de_hold;
always @(posedge clk) begin
    y_hold[0]  <= dh_y;
    cb_hold[0] <= cb_d1[3];
    cr_hold[0] <= cr_d1[3];
    v_hold     <= {v_hold[3:0],  dh_v};
    h_hold     <= {h_hold[3:0],  dh_h};
    de_hold    <= {de_hold[3:0], dh_de};
    for(i=1; i<5; i=i+1) begin
        y_hold[i]  <= y_hold[i-1];
        cb_hold[i] <= cb_hold[i-1];
        cr_hold[i] <= cr_hold[i-1];
    end
end

// Step 4：YCbCr → RGB 
wire [7:0] out_r, out_g, out_b;
wire       f_h, f_v, f_de;
ycbcr_to_rgb u_yuv2rgb (
    .clk(clk),
    .i_y_8b(y_hold[4]), .i_cb_8b(cb_hold[4]), .i_cr_8b(cr_hold[4]),
    .i_h_sync(h_hold[4]), .i_v_sync(v_hold[4]), .i_data_en(de_hold[4]),
    .o_r_8b(out_r), .o_g_8b(out_g), .o_b_8b(out_b),
    .o_h_sync(f_h), .o_v_sync(f_v), .o_data_en(f_de)
);

assign out_vsync  = f_v;
assign out_hsync  = f_h;
assign out_de     = f_de;
assign out_rgb565 = {out_r[7:3], out_g[7:2], out_b[7:3]};

endmodule