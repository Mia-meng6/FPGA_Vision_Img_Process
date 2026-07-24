/*
 * 模块名：skin_detect
 * 功  能：基于 YCbCr 肤色检测，输出二值化肤色 Bit 图
 */

`timescale 1ns/1ps
module skin_detect (
    input        clk,
    input        rst_n,
    // 原始像素输入
    input  [7:0] i_r,
    input  [7:0] i_g,
    input  [7:0] i_b,
    input        i_vsync,
    input        i_href,
    input        i_clken,
    // 肤色二值输出
    output       post_frame_vsync,
    output       post_frame_href,
    output       post_frame_clken,
    output       post_img_Bit       // 1 = 肤色区域
);

// -------------------------------------------------------
// Step 1: RGB → YCbCr 
// -------------------------------------------------------
wire [7:0] ycbcr_cb, ycbcr_cr;
wire       ycbcr_vsync, ycbcr_href, ycbcr_clken;

rgb_to_ycbcr u_rgb2ycbcr (
    .clk        (clk),
    .i_r_8b     (i_r),
    .i_g_8b     (i_g),
    .i_b_8b     (i_b),
    .i_h_sync   (i_href),
    .i_v_sync   (i_vsync),
    .i_data_en  (i_clken),
    .o_y_8b     (),           
    .o_cb_8b    (ycbcr_cb),
    .o_cr_8b    (ycbcr_cr),
    .o_h_sync   (ycbcr_href),
    .o_v_sync   (ycbcr_vsync),
    .o_data_en  (ycbcr_clken)
);

// -------------------------------------------------------
// Step 2: 肤色判断 
// -------------------------------------------------------
reg skin_bit_r;
reg sync_vsync_r, sync_href_r, sync_clken_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        skin_bit_r    <= 1'b0;
        sync_vsync_r  <= 1'b0;
        sync_href_r   <= 1'b0;
        sync_clken_r  <= 1'b0;
    end else begin
        sync_vsync_r <= ycbcr_vsync;
        sync_href_r  <= ycbcr_href;
        sync_clken_r <= ycbcr_clken;
        if (ycbcr_clken && ycbcr_href)
            skin_bit_r <= (ycbcr_cb > 8'd77)  && (ycbcr_cb < 8'd127) &&
                          (ycbcr_cr > 8'd133)  && (ycbcr_cr < 8'd173);
        else
            skin_bit_r <= 1'b0;
    end
end

assign post_frame_vsync = sync_vsync_r;
assign post_frame_href  = sync_href_r;
assign post_frame_clken = sync_clken_r;
assign post_img_Bit     = sync_href_r ? skin_bit_r : 1'b0;

endmodule