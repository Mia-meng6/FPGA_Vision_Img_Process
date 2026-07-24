`timescale 1ns/1ns
// =============================================================================
// Module  : Sketch_Render
// Purpose : 卡通风格最终渲染
// =============================================================================
module Sketch_Render (
    input  wire         clk,
    input  wire         rst_n,

    // 同步信号
    input  wire         smooth_frame_vsync,
    input  wire         smooth_frame_href,
    input  wire         smooth_frame_clken,
    input  wire         edge_bit,
    input  wire [15:0]  aligned_rgb_data,
    // 输出
    output wire         render_frame_vsync,
    output wire         render_frame_href,
    output wire         render_frame_clken,
    output wire [15:0]  render_img_data
);

    // ─── 行坐标计数器────────────────────────────────────────────
    reg [10:0] x_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            x_cnt <= 11'd0;
        else if (smooth_frame_href && smooth_frame_clken)
            x_cnt <= x_cnt + 11'd1;
        else if (!smooth_frame_href)
            x_cnt <= 11'd0;
    end

    // 有效区域
    wire valid_area = (x_cnt >= 11'd3 && x_cnt < (IMG_HDISP - 11'd3));
    parameter [10:0] IMG_HDISP = 11'd640;
    // ─── 色块量化───────────────────────────────────────────
    // RGB565 拆分
    wire [4:0] R = aligned_rgb_data[15:11];
    wire [5:0] G = aligned_rgb_data[10:5];
    wire [4:0] B = aligned_rgb_data[4:0];

    // 只保留高 2 位，再用高位填充低位
    wire [4:0] anime_R = {R[4:3], R[4:3], R[4]};
    wire [5:0] anime_G = {G[5:4], G[5:4], G[5:4]};
    wire [4:0] anime_B = {B[4:3], B[4:3], B[4]};
    wire [15:0] color_pixel = {anime_R, anime_G, anime_B};

    // ─── 同步信号直通 ─────────────────────────────────────────────────────
    assign render_frame_vsync = smooth_frame_vsync;
    assign render_frame_href  = smooth_frame_href;
    assign render_frame_clken = smooth_frame_clken;

    // ─── 输出选择逻辑 ─────────────────────────────────────────────────────
    // 优先级：边界消隐 > 边缘黑线 > 色块彩色
    assign render_img_data = (!valid_area)  ? 16'h0000 :  // 边界置黑
                              edge_bit      ? 16'h0000 :  // 线条置黑（卡通线稿）
                                              color_pixel; // 彩色色块

endmodule