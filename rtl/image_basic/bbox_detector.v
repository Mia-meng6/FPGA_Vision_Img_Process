/*
 * 模块名：bbox_detector
 * 功  能：对二值化肤色图进行逐帧扫描，统计肤色像素的
 *         最小/最大行列坐标，得到手势边界框 (x_min, y_min, x_max, y_max)。
 */

`timescale 1ns/1ps
module bbox_detector #(
    parameter [10:0] IMG_HDISP = 11'd640,
    parameter [10:0] IMG_VDISP = 11'd480
)(
    input        clk,
    input        rst_n,

    // 二值肤色像素流输入
    input        per_frame_vsync,
    input        per_frame_href,
    input        per_frame_clken,
    input        per_img_Bit,       // 1 = 肤色像素

    // 稳定输出（帧末更新）
    output reg [10:0] bbox_x_min,
    output reg [10:0] bbox_x_max,
    output reg [10:0] bbox_y_min,
    output reg [10:0] bbox_y_max,
    output reg        bbox_valid     // 该帧是否检测到肤色区域
);

// -------------------------------------------------------
// vsync 沿检测
// -------------------------------------------------------
reg vsync_d;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) vsync_d <= 1'b0;
    else        vsync_d <= per_frame_vsync;
end
wire vsync_rise = per_frame_vsync & ~vsync_d;   // 帧开始
wire vsync_fall = ~per_frame_vsync & vsync_d;   // 帧结束

// -------------------------------------------------------
// 行列像素计数器
// -------------------------------------------------------
reg [10:0] col_cnt;
reg [10:0] row_cnt;
reg        href_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        col_cnt <= 11'd0;
        row_cnt <= 11'd0;
        href_d  <= 1'b0;
    end else begin
        href_d <= per_frame_href;
        if (vsync_rise) begin
            col_cnt <= 11'd0;
            row_cnt <= 11'd0;
        end else if (per_frame_href && per_frame_clken) begin
            if (col_cnt == IMG_HDISP - 1)
                col_cnt <= 11'd0;
            else
                col_cnt <= col_cnt + 1'b1;
        end else if (!per_frame_href && href_d) begin
            // href 下降沿 → 换行
            col_cnt <= 11'd0;
            row_cnt <= row_cnt + 1'b1;
        end
    end
end

// -------------------------------------------------------
// 帧内极值寄存器
// -------------------------------------------------------
reg [10:0] x_min_r, x_max_r, y_min_r, y_max_r;
reg        found_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_min_r <= 11'h7FF;
        x_max_r <= 11'd0;
        y_min_r <= 11'h7FF;
        y_max_r <= 11'd0;
        found_r <= 1'b0;
    end else if (vsync_rise) begin
        x_min_r <= 11'h7FF;
        x_max_r <= 11'd0;
        y_min_r <= 11'h7FF;
        y_max_r <= 11'd0;
        found_r <= 1'b0;
    end else if (per_frame_href && per_frame_clken && per_img_Bit) begin
        found_r <= 1'b1;
        if (col_cnt < x_min_r) x_min_r <= col_cnt;
        if (col_cnt > x_max_r) x_max_r <= col_cnt;
        if (row_cnt < y_min_r) y_min_r <= row_cnt;
        if (row_cnt > y_max_r) y_max_r <= row_cnt;
    end
end

// -------------------------------------------------------
// 输出
// -------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bbox_x_min <= 11'd0;
        bbox_x_max <= 11'd0;
        bbox_y_min <= 11'd0;
        bbox_y_max <= 11'd0;
        bbox_valid <= 1'b0;
    end else if (vsync_fall) begin
        bbox_valid <= found_r;
        if (found_r) begin
            bbox_x_min <= x_min_r;
            bbox_x_max <= x_max_r;
            bbox_y_min <= y_min_r;
            bbox_y_max <= y_max_r;
        end
    end
end

endmodule