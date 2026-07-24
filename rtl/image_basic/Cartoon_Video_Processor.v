`timescale 1ns/1ns
// =============================================================================
// Module  : Cartoon_Video_Processor
// Purpose : 卡通化视频处理主流水线
// =============================================================================
module Cartoon_Video_Processor
#(
    parameter   [9:0]   IMG_HDISP = 10'd640,
    parameter   [9:0]   IMG_VDISP = 10'd480
)
(
    input               clk,
    input               rst_n,

    input               cmos_frame_vsync,
    input               cmos_frame_href,
    input               cmos_frame_clken,
    input       [15:0]  cmos_frame_data,

    output      [11:0]  face_x_min, output [11:0]  face_x_max,
    output      [11:0]  face_y_min, output [11:0]  face_y_max,

    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_clken,
    output      [15:0]  post_img_data,    // 卡通化图像
    output      [15:0]  post_raw_data     // 对齐的原图
);

// ============================================================================
// [Stage 0.1] 全局 RGB 均值降噪 
// ============================================================================
wire smooth_base_vsync, smooth_base_href, smooth_base_clken;
wire [15:0] smooth_base_rgb;

VIP_RGB_Smooth #(
    .IMG_HDISP(IMG_HDISP)
) u_VIP_RGB_Smooth (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_vsync  (cmos_frame_vsync),
    .in_href   (cmos_frame_href),
    .in_clken  (cmos_frame_clken),
    .in_rgb    (cmos_frame_data),
    .out_vsync (smooth_base_vsync),
    .out_href  (smooth_base_href),
    .out_clken (smooth_base_clken),
    .out_rgb   (smooth_base_rgb)
);

// ============================================================================
// RGB 延迟对齐
// ============================================================================
wire [15:0] aligned_cmos_rgb;
wire        erosion_clken;  //  Stage 7 提供

RGB_Delay_Align #(
    .IMG_HDISP(IMG_HDISP)
) u_RGB_Delay_Align (
    .clk              (clk),
    .rst_n            (rst_n),
    .cmos_clken       (smooth_base_clken),
    .cmos_rgb_data    (smooth_base_rgb),
    .sync_clken       (erosion_clken),
    .aligned_rgb_data (aligned_cmos_rgb)
);

// ============================================================================
// [Stage 1] RGB565 → YCbCr 
// ============================================================================
wire [7:0] post1_img_Y;
wire post1_frame_vsync, post1_frame_href, post1_frame_clken;

rgb_to_ycbcr rgb_to_ycbcr_u0 (
    .clk       (clk),
    .i_r_8b    ({smooth_base_rgb[15:11], 3'b0}),
    .i_g_8b    ({smooth_base_rgb[10:5],  2'b0}),
    .i_b_8b    ({smooth_base_rgb[4:0],   3'b0}),
    .i_h_sync  (smooth_base_href),
    .i_v_sync  (smooth_base_vsync),
    .i_data_en (smooth_base_clken),
    .o_y_8b    (post1_img_Y),
    .o_h_sync  (post1_frame_href),
    .o_v_sync  (post1_frame_vsync),
    .o_data_en (post1_frame_clken)
);

// ============================================================================
// [Stage 2] 8-bit 3×3 亮度矩阵 
// ============================================================================
wire mat1_vsync, mat1_href, mat1_clken;
wire [7:0] mat1_p11, mat1_p12, mat1_p13;
wire [7:0] mat1_p21, mat1_p22, mat1_p23;
wire [7:0] mat1_p31, mat1_p32, mat1_p33;

VIP_Matrix_Generate_3X3_8Bit #(.IMG_HDISP(IMG_HDISP)) u_VIP_Matrix_8Bit_1 (
    .clk               (clk), .rst_n             (rst_n),
    .per_frame_vsync   (post1_frame_vsync),
    .per_frame_href    (post1_frame_href),
    .per_frame_clken   (post1_frame_clken),
    .per_img_Y         (post1_img_Y),
    .matrix_frame_vsync(mat1_vsync),
    .matrix_frame_href (mat1_href),
    .matrix_frame_clken(mat1_clken),
    .matrix_p11(mat1_p11), .matrix_p12(mat1_p12), .matrix_p13(mat1_p13),
    .matrix_p21(mat1_p21), .matrix_p22(mat1_p22), .matrix_p23(mat1_p23),
    .matrix_p31(mat1_p31), .matrix_p32(mat1_p32), .matrix_p33(mat1_p33)
);

// ============================================================================
// [Stage 3] 保边平滑滤波  
// ============================================================================
wire smooth_frame_vsync, smooth_frame_href, smooth_frame_clken;
wire [7:0] smooth_img_Y;

Cartoon_Smoothing_Filter u_Cartoon_Smoothing_Filter (
    .clk                 (clk), .rst_n               (rst_n),
    .matrix_frame_vsync  (mat1_vsync),
    .matrix_frame_href   (mat1_href),
    .matrix_frame_clken  (mat1_clken),
    .matrix_p11(mat1_p11), .matrix_p12(mat1_p12), .matrix_p13(mat1_p13),
    .matrix_p21(mat1_p21), .matrix_p22(mat1_p22), .matrix_p23(mat1_p23),
    .matrix_p31(mat1_p31), .matrix_p32(mat1_p32), .matrix_p33(mat1_p33),
    .smooth_threshold    (8'd20),
    .smooth_frame_vsync  (smooth_frame_vsync),
    .smooth_frame_href   (smooth_frame_href),
    .smooth_frame_clken  (smooth_frame_clken),
    .smooth_img_Y        (smooth_img_Y)
);

// ============================================================================
// [Stage 4] 8-bit 3×3 亮度矩阵 
// ============================================================================
wire mat2_vsync, mat2_href, mat2_clken;
wire [7:0] mat2_p11, mat2_p12, mat2_p13;
wire [7:0] mat2_p21, mat2_p22, mat2_p23;
wire [7:0] mat2_p31, mat2_p32, mat2_p33;

VIP_Matrix_Generate_3X3_8Bit #(.IMG_HDISP(IMG_HDISP)) u_VIP_Matrix_8Bit_2 (
    .clk               (clk), .rst_n             (rst_n),
    .per_frame_vsync   (smooth_frame_vsync),
    .per_frame_href    (smooth_frame_href),
    .per_frame_clken   (smooth_frame_clken),
    .per_img_Y         (smooth_img_Y),
    .matrix_frame_vsync(mat2_vsync),
    .matrix_frame_href (mat2_href),
    .matrix_frame_clken(mat2_clken),
    .matrix_p11(mat2_p11), .matrix_p12(mat2_p12), .matrix_p13(mat2_p13),
    .matrix_p21(mat2_p21), .matrix_p22(mat2_p22), .matrix_p23(mat2_p23),
    .matrix_p31(mat2_p31), .matrix_p32(mat2_p32), .matrix_p33(mat2_p33)
);

// ============================================================================
// [Stage 5] Sobel 边缘检测  
// ============================================================================
wire sobel_vsync, sobel_href, sobel_clken, sobel_edge_bit;

Sobel_Edge_Detector u_Sobel_Edge_Detector (
    .clk                (clk), .rst_n              (rst_n),
    .matrix_frame_vsync (mat2_vsync),
    .matrix_frame_href  (mat2_href),
    .matrix_frame_clken (mat2_clken),
    .matrix_p11(mat2_p11), .matrix_p12(mat2_p12), .matrix_p13(mat2_p13),
    .matrix_p21(mat2_p21), .matrix_p22(mat2_p22), .matrix_p23(mat2_p23),
    .matrix_p31(mat2_p31), .matrix_p32(mat2_p32), .matrix_p33(mat2_p33),
    .sobel_threshold    (8'd200),
    .sobel_frame_vsync  (sobel_vsync),
    .sobel_frame_href   (sobel_href),
    .sobel_frame_clken  (sobel_clken),
    .sobel_edge_bit     (sobel_edge_bit)
);

// ============================================================================
// [Stage 6] 形态学膨胀  
// ============================================================================
wire dilated_vsync, dilated_href, dilated_clken, dilated_edge_bit;

VIP_Bit_Dilation_Detector #(
    .IMG_HDISP(IMG_HDISP), .IMG_VDISP(IMG_VDISP)
) u_VIP_Bit_Dilation (
    .clk             (clk), .rst_n           (rst_n),
    .per_frame_vsync (sobel_vsync), .per_frame_href  (sobel_href),
    .per_frame_clken (sobel_clken), .per_img_Bit     (sobel_edge_bit),
    .post_frame_vsync(dilated_vsync), .post_frame_href (dilated_href),
    .post_frame_clken(dilated_clken), .post_img_Bit    (dilated_edge_bit)
);

// ============================================================================
// [Stage 7] 形态学腐蚀（闭运算 = 膨胀 + 腐蚀） 
// ============================================================================
wire erosion_vsync, erosion_href;
wire erosion_edge_bit;

VIP_Bit_Erosion_Detector #(
    .IMG_HDISP(IMG_HDISP), .IMG_VDISP(IMG_VDISP)
) u_VIP_Bit_Erosion (
    .clk             (clk), .rst_n           (rst_n),
    .per_frame_vsync (dilated_vsync), .per_frame_href  (dilated_href),
    .per_frame_clken (dilated_clken), .per_img_Bit     (dilated_edge_bit),
    .post_frame_vsync(erosion_vsync), .post_frame_href (erosion_href),
    .post_frame_clken(erosion_clken), .post_img_Bit    (erosion_edge_bit)
);

// ============================================================================
// [Stage 8] 最终渲染：色块量化 + 边缘黑线叠加
// ============================================================================
wire sketch_vsync, sketch_href, sketch_clken;
wire [15:0] sketch_rgb565;

Sketch_Render u_Sketch_Render (
    .clk               (clk), .rst_n             (rst_n),
    .smooth_frame_vsync(erosion_vsync),
    .smooth_frame_href (erosion_href),
    .smooth_frame_clken(erosion_clken),
    .edge_bit          (erosion_edge_bit),
    .aligned_rgb_data  (aligned_cmos_rgb),
    .render_frame_vsync(sketch_vsync),
    .render_frame_href (sketch_href),
    .render_frame_clken(sketch_clken),
    .render_img_data   (sketch_rgb565)
);

// ============================================================================
// 输出赋值
// ============================================================================
assign face_x_min = 12'd0;
assign face_x_max = 12'd0;
assign face_y_min = 12'd0;
assign face_y_max = 12'd0;

assign post_frame_vsync = sketch_vsync;
assign post_frame_href  = sketch_href;
assign post_frame_clken = sketch_clken;
assign post_img_data    = sketch_rgb565;

assign post_raw_data    = aligned_cmos_rgb;

endmodule