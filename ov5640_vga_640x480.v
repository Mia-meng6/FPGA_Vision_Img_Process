`timescale 1ns/1ns
// =============================================================================
// 模块名：ov5640_vga_640x480 
// =============================================================================
module ov5640_vga_640x480 (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    input  wire        ov5640_pclk,
    input  wire        ov5640_vsync,
    input  wire        ov5640_href,
    input  wire [7:0]  ov5640_data,
  
    output wire        ov5640_rst_n,
    output wire        ov5640_pwdn,
    output wire        ov5640_xclk,
    output wire        sccb_scl,
    inout  wire        sccb_sda,

    output wire        sdram_clk,
    output wire        sdram_cke,
    output wire        sdram_cs_n,
    output wire        sdram_ras_n,
    output wire        sdram_cas_n,
    output wire        sdram_we_n,
    output wire [1:0]  sdram_ba,
    output wire [12:0] sdram_addr,
    inout  wire [15:0] sdram_dq,

    output wire        vga_hs,
    output wire        vga_vs,
    output wire [15:0] vga_rgb,

    input  wire        uart_rxd,     
    output wire        uart_txd,     

    input  wire        key_inc,      
    input  wire        key_dec,      

    output wire        LED3          
);

parameter H_PIXEL      = 24'd640;
parameter V_PIXEL      = 24'd480;
parameter WR_BURST_LEN = 10'd512;

parameter THRESH_HYST  = 8'd12;
parameter [3:0] PRE_MAJ  = 4'd6;
parameter [3:0] POST_MAJ = 4'd5;
parameter CLK_FREQ      = 50_000_000;
parameter UART_BPS_FAST = 115200;
parameter UART_BPS_SLOW = 9600;

wire        clk_100m;
wire        clk_100m_shift;
wire        clk_25m;
wire        locked;
wire        cfg_done;
wire        sdram_init_done;
wire        sys_init_done;

wire        wr_en;
wire [15:0] wr_data;
wire        rst_n;

assign rst_n = sys_rst_n & locked;

wire [7:0]  img_r_w;
assign img_r_w = {wr_data[15:11], 3'b000};

wire [7:0]  img_g_w;
assign img_g_w = {wr_data[10:5],  2'b00};

wire [7:0]  img_b_w;
assign img_b_w = {wr_data[4:0],   3'b000};

wire [23:0] rgb888_w;
assign rgb888_w = {img_r_w, img_g_w, img_b_w};

wire [7:0]  he_y;
wire        he_valid;
wire        he_vsync;

Histogram_top u_hist_top (
    .clk     (ov5640_pclk),
    .rst_n   (rst_n),
    .i_rgb   (rgb888_w),
    .i_vsync (ov5640_vsync),
    .i_hsync (ov5640_href),
    .i_valid (wr_en),
    .o_y     (he_y),
    .o_vsync (he_vsync), 
    .o_hsync (),
    .o_valid (he_valid)
);

wire [15:0] he_rgb565;
assign he_rgb565 = {he_y[7:3], he_y[7:2], he_y[7:3]};

wire [7:0]  gray_y_w;
assign gray_y_w = (img_r_w >> 2) + (img_g_w >> 1) + (img_b_w >> 2);

wire [15:0] gray_rgb565;
assign gray_rgb565 = {gray_y_w[7:3], gray_y_w[7:2], gray_y_w[7:3]};

wire        inc_key_flag;
wire        dec_key_flag;

key_filter u_key_inc(
    .sys_clk   (clk_25m),
    .sys_rst_n (rst_n),
    .key_in    (key_inc),
    .key_flag  (inc_key_flag),
    .key_state ()
);

key_filter u_key_dec(
    .sys_clk   (clk_25m),
    .sys_rst_n (rst_n),
    .key_in    (key_dec),
    .key_flag  (dec_key_flag),
    .key_state ()
);

reg         inc_tog;
reg         dec_tog;

always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin 
        inc_tog <= 1'b0;
        dec_tog <= 1'b0; 
    end else begin 
        if (inc_key_flag) begin
            inc_tog <= ~inc_tog;
        end else begin
            inc_tog <= inc_tog;
        end
        if (dec_key_flag) begin
            dec_tog <= ~dec_tog;
        end else begin
            dec_tog <= dec_tog;
        end
    end
end

reg [2:0]   inc_sync3;
reg [2:0]   dec_sync3;

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin 
        inc_sync3 <= 3'b0;
        dec_sync3 <= 3'b0; 
    end else begin 
        inc_sync3 <= {inc_sync3[1:0], inc_tog};
        dec_sync3 <= {dec_sync3[1:0], dec_tog}; 
    end
end

wire        inc_pulse;
assign inc_pulse = inc_sync3[1] ^ inc_sync3[2];

wire        dec_pulse;
assign dec_pulse = dec_sync3[1] ^ dec_sync3[2];

localparam [7:0] THRESHOLD_MIN  = 8'd10;
localparam [7:0] THRESHOLD_MAX  = 8'd250;
localparam [7:0] THRESHOLD_STEP = 8'd5;
localparam [7:0] THRESHOLD_DFT  = 8'd60;

reg [7:0]   morph_threshold;

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin
        morph_threshold <= THRESHOLD_DFT;
    end else begin
        if (inc_pulse && morph_threshold <= THRESHOLD_MAX - THRESHOLD_STEP) begin
            morph_threshold <= morph_threshold + THRESHOLD_STEP;
        end else if (dec_pulse && morph_threshold >= THRESHOLD_MIN + THRESHOLD_STEP) begin
            morph_threshold <= morph_threshold - THRESHOLD_STEP;
        end else begin
            morph_threshold <= morph_threshold;
        end
    end
end

wire [7:0]  morph_gray_y; 
wire        morph_gray_vsync;
wire        morph_gray_href;
wire        morph_gray_en;

rgb_to_ycbcr u_rgb2ycbcr (
    .clk       (ov5640_pclk), 
    .i_r_8b    (img_r_w), 
    .i_g_8b    (img_g_w), 
    .i_b_8b    (img_b_w),
    .i_h_sync  (ov5640_href), 
    .i_v_sync  (ov5640_vsync), 
    .i_data_en (wr_en),
    .o_y_8b    (morph_gray_y), 
    .o_cb_8b   (), 
    .o_cr_8b   (),
    .o_h_sync  (morph_gray_href), 
    .o_v_sync  (morph_gray_vsync), 
    .o_data_en (morph_gray_en)
);

wire        gsm_mat_vsync;
wire        gsm_mat_href;
wire        gsm_mat_en;

wire [7:0]  gsm_p11;
wire [7:0]  gsm_p12;
wire [7:0]  gsm_p13;

wire [7:0]  gsm_p21;
wire [7:0]  gsm_p22;
wire [7:0]  gsm_p23;

wire [7:0]  gsm_p31;
wire [7:0]  gsm_p32;
wire [7:0]  gsm_p33;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP (H_PIXEL[9:0])
) u_gsm_matrix (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .per_frame_vsync   (morph_gray_vsync), 
    .per_frame_href    (morph_gray_href),
    .per_frame_clken   (morph_gray_en), 
    .per_img_Y         (morph_gray_y), 
    .matrix_frame_vsync(gsm_mat_vsync),
    .matrix_frame_href (gsm_mat_href), 
    .matrix_frame_clken(gsm_mat_en),
    .matrix_p11        (gsm_p11), 
    .matrix_p12        (gsm_p12), 
    .matrix_p13        (gsm_p13),
    .matrix_p21        (gsm_p21), 
    .matrix_p22        (gsm_p22), 
    .matrix_p23        (gsm_p23),
    .matrix_p31        (gsm_p31), 
    .matrix_p32        (gsm_p32), 
    .matrix_p33        (gsm_p33)
);

wire        smooth_y_vsync;
wire        smooth_y_href;
wire        smooth_y_en; 
wire [7:0]  smooth_y;

Cartoon_Smoothing_Filter u_gray_smooth (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .matrix_frame_vsync(gsm_mat_vsync), 
    .matrix_frame_href (gsm_mat_href), 
    .matrix_frame_clken(gsm_mat_en),
    .matrix_p11        (gsm_p11), 
    .matrix_p12        (gsm_p12), 
    .matrix_p13        (gsm_p13), 
    .matrix_p21        (gsm_p21), 
    .matrix_p22        (gsm_p22), 
    .matrix_p23        (gsm_p23),
    .matrix_p31        (gsm_p31), 
    .matrix_p32        (gsm_p32), 
    .matrix_p33        (gsm_p33), 
    .smooth_threshold  (8'd20),
    .smooth_frame_vsync(smooth_y_vsync), 
    .smooth_frame_href (smooth_y_href), 
    .smooth_frame_clken(smooth_y_en), 
    .smooth_img_Y      (smooth_y)
);

wire [7:0]  threshold_high;
assign threshold_high = (morph_threshold >= (8'd255 - THRESH_HYST)) ? 8'd255 : (morph_threshold + THRESH_HYST);

wire [7:0]  threshold_low;
assign threshold_low = (morph_threshold <= THRESH_HYST) ? 8'd0 : (morph_threshold - THRESH_HYST);

reg         bit_data_raw;
reg         bit_valid_raw;
reg         bit_href_raw;
reg         bit_vsync_raw;
reg         line_hyst_seed;
reg [7:0]   gray_px_prev;

wire [8:0]  gray_pair;
assign gray_pair = {1'b0, smooth_y} + {1'b0, gray_px_prev};

wire [7:0]  gray_h_sm;
assign gray_h_sm = line_hyst_seed ? smooth_y : gray_pair[8:1];

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin
        bit_data_raw   <= 1'b0;
        bit_valid_raw  <= 1'b0; 
        bit_href_raw   <= 1'b0; 
        bit_vsync_raw  <= 1'b0; 
        line_hyst_seed <= 1'b1;
        gray_px_prev   <= 8'd0;
    end else begin
        bit_valid_raw <= smooth_y_en;
        bit_href_raw  <= smooth_y_href; 
        bit_vsync_raw <= smooth_y_vsync;
        
        if (!smooth_y_href) begin 
            line_hyst_seed <= 1'b1;
            gray_px_prev   <= 8'd0; 
        end else if (smooth_y_en) begin
            if (line_hyst_seed) begin 
                bit_data_raw   <= (gray_h_sm > morph_threshold);
                line_hyst_seed <= 1'b0; 
            end else if (gray_h_sm >= threshold_high) begin
                bit_data_raw <= 1'b1;
            end else if (gray_h_sm <= threshold_low) begin
                bit_data_raw <= 1'b0;
            end else begin
                bit_data_raw <= bit_data_raw;
            end
            gray_px_prev <= smooth_y;
        end
    end
end

wire        pre_vsync;
wire        pre_href;
wire        pre_en;

wire        pre_p11;
wire        pre_p12;
wire        pre_p13;
wire        pre_p21;
wire        pre_p22;
wire        pre_p23;

wire        pre_p31;
wire        pre_p32;
wire        pre_p33;

wire [3:0]  pre_sum;
assign pre_sum = pre_p11 + pre_p12 + pre_p13 + pre_p21 + pre_p22 + pre_p23 + pre_p31 + pre_p32 + pre_p33;

reg         bit_data_flt;

VIP_Matrix_Generate_3X3_1Bit #(
    .IMG_HDISP (H_PIXEL[9:0]), 
    .IMG_VDISP (V_PIXEL[9:0])
) u_pre_filter (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .per_frame_vsync   (bit_vsync_raw), 
    .per_frame_href    (bit_href_raw),
    .per_frame_clken   (bit_valid_raw), 
    .per_img_Bit       (bit_data_raw), 
    .matrix_frame_vsync(pre_vsync), 
    .matrix_frame_href (pre_href),
    .matrix_frame_clken(pre_en), 
    .matrix_p11        (pre_p11), 
    .matrix_p12        (pre_p12), 
    .matrix_p13        (pre_p13),
    .matrix_p21        (pre_p21), 
    .matrix_p22        (pre_p22), 
    .matrix_p23        (pre_p23), 
    .matrix_p31        (pre_p31), 
    .matrix_p32        (pre_p32), 
    .matrix_p33        (pre_p33)
);

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin
        bit_data_flt <= 1'b0;
    end else begin
        if (pre_en) begin
            bit_data_flt <= (pre_sum >= PRE_MAJ);
        end else begin
            bit_data_flt <= bit_data_flt;
        end
    end
end

reg         pre_vsync_d;
reg         pre_href_d;
reg         pre_en_d;

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin 
        pre_vsync_d <= 1'b0;
        pre_href_d  <= 1'b0; 
        pre_en_d    <= 1'b0;
    end else begin 
        pre_vsync_d <= pre_vsync; 
        pre_href_d  <= pre_href;
        pre_en_d    <= pre_en; 
    end
end

wire        erode_bit;
wire        erode_vsync;
wire        erode_href;
wire        erode_en;

VIP_Bit_Erosion_Detector #(
    .IMG_HDISP (H_PIXEL[9:0]), 
    .IMG_VDISP (V_PIXEL[9:0])
) u_erode (
    .clk              (ov5640_pclk), 
    .rst_n            (rst_n), 
    .per_frame_vsync  (pre_vsync_d), 
    .per_frame_href   (pre_href_d),
    .per_frame_clken  (pre_en_d),    
    .per_img_Bit      (bit_data_flt), 
    .post_frame_vsync (erode_vsync), 
    .post_frame_href  (erode_href),
    .post_frame_clken (erode_en),    
    .post_img_Bit     (erode_bit)
);

wire        erode_post_mat_vsync;
wire        erode_post_mat_href;
wire        erode_post_mat_en;

wire        erode_post_p11;
wire        erode_post_p12;
wire        erode_post_p13;

wire        erode_post_p21;
wire        erode_post_p22;
wire        erode_post_p23;

wire        erode_post_p31;
wire        erode_post_p32;
wire        erode_post_p33;

wire [3:0]  erode_post_sum;
assign erode_post_sum = erode_post_p11 + erode_post_p12 + erode_post_p13 + erode_post_p21 + erode_post_p22 + erode_post_p23 + erode_post_p31 + erode_post_p32 + erode_post_p33;

reg         erode_clean_bit;
reg         erode_clean_en;
reg         erode_clean_href;
reg         erode_clean_vsync;

VIP_Matrix_Generate_3X3_1Bit #(
    .IMG_HDISP (H_PIXEL[9:0]), 
    .IMG_VDISP (V_PIXEL[9:0])
) u_erode_post_filter (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .per_frame_vsync   (erode_vsync), 
    .per_frame_href    (erode_href), 
    .per_frame_clken   (erode_en), 
    .per_img_Bit       (erode_bit),
    .matrix_frame_vsync(erode_post_mat_vsync), 
    .matrix_frame_href (erode_post_mat_href), 
    .matrix_frame_clken(erode_post_mat_en),
    .matrix_p11        (erode_post_p11), 
    .matrix_p12        (erode_post_p12), 
    .matrix_p13        (erode_post_p13), 
    .matrix_p21        (erode_post_p21), 
    .matrix_p22        (erode_post_p22), 
    .matrix_p23        (erode_post_p23),
    .matrix_p31        (erode_post_p31), 
    .matrix_p32        (erode_post_p32), 
    .matrix_p33        (erode_post_p33)
);

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin 
        erode_clean_bit   <= 1'b0;
        erode_clean_en    <= 1'b0; 
        erode_clean_href  <= 1'b0; 
        erode_clean_vsync <= 1'b0;
    end else begin 
        erode_clean_en    <= erode_post_mat_en;
        erode_clean_href  <= erode_post_mat_href; 
        erode_clean_vsync <= erode_post_mat_vsync;
        if (erode_post_mat_en) begin
            erode_clean_bit <= (erode_post_sum >= POST_MAJ);
        end else begin
            erode_clean_bit <= erode_clean_bit;
        end
    end
end

wire        dil2_bit;
wire        dil2_vsync;
wire        dil2_href;
wire        dil2_en;

VIP_Bit_Dilation_Detector #(
    .IMG_HDISP (H_PIXEL[9:0]), 
    .IMG_VDISP (V_PIXEL[9:0])
) u_dilate_after_erode (
    .clk              (ov5640_pclk), 
    .rst_n            (rst_n), 
    .per_frame_vsync  (erode_clean_vsync), 
    .per_frame_href   (erode_clean_href),
    .per_frame_clken  (erode_clean_en), 
    .per_img_Bit      (erode_clean_bit), 
    .post_frame_vsync (dil2_vsync), 
    .post_frame_href  (dil2_href),
    .post_frame_clken (dil2_en), 
    .post_img_Bit     (dil2_bit)
);

wire        open_post_mat_vsync;
wire        open_post_mat_href;
wire        open_post_mat_en;

wire        open_post_p11;
wire        open_post_p12;
wire        open_post_p13;

wire        open_post_p21;
wire        open_post_p22;
wire        open_post_p23;

wire        open_post_p31;
wire        open_post_p32;
wire        open_post_p33;

wire [3:0]  open_post_sum;
assign open_post_sum = open_post_p11 + open_post_p12 + open_post_p13 + open_post_p21 + open_post_p22 + open_post_p23 + open_post_p31 + open_post_p32 + open_post_p33;

reg         open_clean_bit;
reg         open_clean_en;
reg         open_clean_href;
reg         open_clean_vsync;

VIP_Matrix_Generate_3X3_1Bit #(
    .IMG_HDISP (H_PIXEL[9:0]), 
    .IMG_VDISP (V_PIXEL[9:0])
) u_open_post_filter (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .per_frame_vsync   (dil2_vsync), 
    .per_frame_href    (dil2_href), 
    .per_frame_clken   (dil2_en), 
    .per_img_Bit       (dil2_bit),
    .matrix_frame_vsync(open_post_mat_vsync), 
    .matrix_frame_href (open_post_mat_href), 
    .matrix_frame_clken(open_post_mat_en),
    .matrix_p11        (open_post_p11), 
    .matrix_p12        (open_post_p12), 
    .matrix_p13        (open_post_p13), 
    .matrix_p21        (open_post_p21), 
    .matrix_p22        (open_post_p22), 
    .matrix_p23        (open_post_p23),
    .matrix_p31        (open_post_p31), 
    .matrix_p32        (open_post_p32), 
    .matrix_p33        (open_post_p33)
);

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin 
        open_clean_bit   <= 1'b0;
        open_clean_en    <= 1'b0; 
        open_clean_href  <= 1'b0; 
        open_clean_vsync <= 1'b0;
    end else begin 
        open_clean_en    <= open_post_mat_en;
        open_clean_href  <= open_post_mat_href; 
        open_clean_vsync <= open_post_mat_vsync;
        if (open_post_mat_en) begin
            open_clean_bit <= (open_post_sum >= POST_MAJ);
        end else begin
            open_clean_bit <= open_clean_bit;
        end
    end
end

wire        morph_wr_en;
assign morph_wr_en = open_clean_en;

wire [15:0] morph_wr_data;
assign morph_wr_data = open_clean_bit ? 16'hFFFF : 16'h0000;

// ==========================================
// 5. RGB转HSV处理流水线 (算法6)
// ==========================================
wire [7:0]  hsv_cam_r;
assign hsv_cam_r = {wr_data[15:11], wr_data[15:13]};

wire [7:0]  hsv_cam_g;
assign hsv_cam_g = {wr_data[10:5],  wr_data[10:9]};

wire [7:0]  hsv_cam_b;
assign hsv_cam_b = {wr_data[4:0],   wr_data[4:2]};

wire        r_matrix_vsync;
wire        r_matrix_href;
wire        r_matrix_clken;

wire [7:0]  r_p11;
wire [7:0]  r_p12;
wire [7:0]  r_p13;

wire [7:0]  r_p21;
wire [7:0]  r_p22;
wire [7:0]  r_p23;

wire [7:0]  r_p31;
wire [7:0]  r_p32;
wire [7:0]  r_p33;

wire [7:0]  g_p11;
wire [7:0]  g_p12;
wire [7:0]  g_p13;

wire [7:0]  g_p21;
wire [7:0]  g_p22;
wire [7:0]  g_p23;

wire [7:0]  g_p31;
wire [7:0]  g_p32;
wire [7:0]  g_p33;

wire [7:0]  b_p11;
wire [7:0]  b_p12;
wire [7:0]  b_p13;

wire [7:0]  b_p21;
wire [7:0]  b_p22;
wire [7:0]  b_p23;

wire [7:0]  b_p31;
wire [7:0]  b_p32;
wire [7:0]  b_p33;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP(10'd640)
) u_hsv_r_matrix (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .per_frame_vsync   (ov5640_vsync), 
    .per_frame_href    (ov5640_href), 
    .per_frame_clken   (wr_en), 
    .per_img_Y         (hsv_cam_r), 
    .matrix_frame_vsync(r_matrix_vsync), 
    .matrix_frame_href (r_matrix_href), 
    .matrix_frame_clken(r_matrix_clken), 
    .matrix_p11        (r_p11),
    .matrix_p12        (r_p12),
    .matrix_p13        (r_p13), 
    .matrix_p21        (r_p21),
    .matrix_p22        (r_p22),
    .matrix_p23        (r_p23), 
    .matrix_p31        (r_p31),
    .matrix_p32        (r_p32),
    .matrix_p33        (r_p33)
);

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP(10'd640)
) u_hsv_g_matrix (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .per_frame_vsync   (ov5640_vsync), 
    .per_frame_href    (ov5640_href), 
    .per_frame_clken   (wr_en), 
    .per_img_Y         (hsv_cam_g), 
    .matrix_frame_vsync(),
    .matrix_frame_href (),
    .matrix_frame_clken(),
    .matrix_p11        (g_p11),
    .matrix_p12        (g_p12),
    .matrix_p13        (g_p13), 
    .matrix_p21        (g_p21),
    .matrix_p22        (g_p22),
    .matrix_p23        (g_p23), 
    .matrix_p31        (g_p31),
    .matrix_p32        (g_p32),
    .matrix_p33        (g_p33)
);

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP(10'd640)
) u_hsv_b_matrix (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .per_frame_vsync   (ov5640_vsync), 
    .per_frame_href    (ov5640_href), 
    .per_frame_clken   (wr_en), 
    .per_img_Y         (hsv_cam_b), 
    .matrix_frame_vsync(),
    .matrix_frame_href (),
    .matrix_frame_clken(),
    .matrix_p11        (b_p11),
    .matrix_p12        (b_p12),
    .matrix_p13        (b_p13), 
    .matrix_p21        (b_p21),
    .matrix_p22        (b_p22),
    .matrix_p23        (b_p23), 
    .matrix_p31        (b_p31),
    .matrix_p32        (b_p32),
    .matrix_p33        (b_p33)
);

wire        smooth_vsync;
wire        smooth_href;
wire        smooth_clken; 

wire [7:0]  smooth_r;
wire [7:0]  smooth_g;
wire [7:0]  smooth_b;

Cartoon_Smoothing_Filter u_hsv_smooth_r (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .matrix_frame_vsync(r_matrix_vsync), 
    .matrix_frame_href (r_matrix_href), 
    .matrix_frame_clken(r_matrix_clken), 
    .matrix_p11        (r_p11),
    .matrix_p12        (r_p12),
    .matrix_p13        (r_p13), 
    .matrix_p21        (r_p21),
    .matrix_p22        (r_p22),
    .matrix_p23        (r_p23), 
    .matrix_p31        (r_p31),
    .matrix_p32        (r_p32),
    .matrix_p33        (r_p33), 
    .smooth_threshold  (8'd12), 
    .smooth_frame_vsync(smooth_vsync), 
    .smooth_frame_href (smooth_href), 
    .smooth_frame_clken(smooth_clken), 
    .smooth_img_Y      (smooth_r)
);

Cartoon_Smoothing_Filter u_hsv_smooth_g (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .matrix_frame_vsync(r_matrix_vsync), 
    .matrix_frame_href (r_matrix_href), 
    .matrix_frame_clken(r_matrix_clken), 
    .matrix_p11        (g_p11),
    .matrix_p12        (g_p12),
    .matrix_p13        (g_p13), 
    .matrix_p21        (g_p21),
    .matrix_p22        (g_p22),
    .matrix_p23        (g_p23), 
    .matrix_p31        (g_p31),
    .matrix_p32        (g_p32),
    .matrix_p33        (g_p33), 
    .smooth_threshold  (8'd12), 
    .smooth_frame_vsync(),
    .smooth_frame_href (),
    .smooth_frame_clken(),
    .smooth_img_Y      (smooth_g)
);

Cartoon_Smoothing_Filter u_hsv_smooth_b (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .matrix_frame_vsync(r_matrix_vsync), 
    .matrix_frame_href (r_matrix_href), 
    .matrix_frame_clken(r_matrix_clken), 
    .matrix_p11        (b_p11),
    .matrix_p12        (b_p12),
    .matrix_p13        (b_p13), 
    .matrix_p21        (b_p21),
    .matrix_p22        (b_p22),
    .matrix_p23        (b_p23), 
    .matrix_p31        (b_p31),
    .matrix_p32        (b_p32),
    .matrix_p33        (b_p33), 
    .smooth_threshold  (8'd12), 
    .smooth_frame_vsync(),
    .smooth_frame_href (),
    .smooth_frame_clken(),
    .smooth_img_Y      (smooth_b)
);

wire        hsv_en; 
wire [23:0] hsv_data;

RGB2HSV u_rgb2hsv (
    .I_clk   (ov5640_pclk), 
    .I_rst_n (rst_n), 
    .I_tlast (1'b0), 
    .I_tuser (1'b0), 
    .I_tdata ({smooth_r, smooth_g, smooth_b}), 
    .I_tvalid(smooth_clken), 
    .O_tdata (hsv_data), 
    .O_tvalid(hsv_en), 
    .O_tready(1'b1)
);

reg [25:0]  hsv_vsync_sr;
reg [25:0]  hsv_href_sr;

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin 
        hsv_vsync_sr <= 26'd0;
        hsv_href_sr  <= 26'd0; 
    end else begin 
        hsv_vsync_sr <= {hsv_vsync_sr[24:0], smooth_vsync};
        hsv_href_sr  <= {hsv_href_sr[24:0],  smooth_href}; 
    end
end

wire        hsv_vsync_d;
assign hsv_vsync_d = hsv_vsync_sr[25];

wire        hsv_href_d;
assign hsv_href_d = hsv_href_sr[25];

wire [7:0]  hue;
assign hue = hsv_data[23:16];

wire [7:0]  sat;
assign sat = hsv_data[15:8];

wire [7:0]  val;
assign val = hsv_data[7:0];

wire [15:0] hsv_pseudo_rgb565;
assign hsv_pseudo_rgb565 = {hue[7:3], sat[7:2], val[7:3]}; 

wire        hsv_mask_pre;
assign hsv_mask_pre = (val >= 8'd20);

reg [15:0]  hsv_px_d1;
reg [15:0]  hsv_px_d2;
reg [15:0]  hsv_px_d3;

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin 
        hsv_px_d1 <= 16'd0;
        hsv_px_d2 <= 16'd0; 
        hsv_px_d3 <= 16'd0; 
    end else if (hsv_en) begin 
        hsv_px_d1 <= hsv_pseudo_rgb565;
        hsv_px_d2 <= hsv_px_d1; 
        hsv_px_d3 <= hsv_px_d2; 
    end
end

wire        mask_matrix_vsync;
wire        mask_matrix_href;
wire        mask_matrix_clken;

wire        mask_p11;
wire        mask_p12;
wire        mask_p13;

wire        mask_p21;
wire        mask_p22;
wire        mask_p23;

wire        mask_p31;
wire        mask_p32;
wire        mask_p33;

VIP_Matrix_Generate_3X3_1Bit #(
    .IMG_HDISP(10'd640), 
    .IMG_VDISP(10'd480)
) u_hsv_mask_matrix (
    .clk               (ov5640_pclk), 
    .rst_n             (rst_n), 
    .per_frame_vsync   (hsv_vsync_d), 
    .per_frame_href    (hsv_href_d), 
    .per_frame_clken   (hsv_en), 
    .per_img_Bit       (hsv_mask_pre), 
    .matrix_frame_vsync(mask_matrix_vsync), 
    .matrix_frame_href (mask_matrix_href), 
    .matrix_frame_clken(mask_matrix_clken), 
    .matrix_p11        (mask_p11),
    .matrix_p12        (mask_p12),
    .matrix_p13        (mask_p13), 
    .matrix_p21        (mask_p21),
    .matrix_p22        (mask_p22),
    .matrix_p23        (mask_p23), 
    .matrix_p31        (mask_p31),
    .matrix_p32        (mask_p32),
    .matrix_p33        (mask_p33)
);

wire [3:0]  vote_sum;
assign vote_sum = mask_p11 + mask_p12 + mask_p13 + mask_p21 + mask_p22 + mask_p23 + mask_p31 + mask_p32 + mask_p33;

reg [1:0]   post_vsync_r;
reg [1:0]   post_href_r;
reg [1:0]   post_clken_r; 
reg         hsv_mask_vote;

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin 
        post_vsync_r  <= 2'b0;
        post_href_r   <= 2'b0; 
        post_clken_r  <= 2'b0; 
        hsv_mask_vote <= 1'b0;
    end else begin 
        post_vsync_r  <= {post_vsync_r[0], mask_matrix_vsync};
        post_href_r   <= {post_href_r[0],  mask_matrix_href}; 
        post_clken_r  <= {post_clken_r[0], mask_matrix_clken}; 
        hsv_mask_vote <= (vote_sum >= 4'd5); 
    end
end

wire        hsv_post_clken;
assign hsv_post_clken = post_clken_r[1]; 

wire        hsv_post_href;
assign hsv_post_href = post_href_r[1];

wire        hsv_wr_en;
assign hsv_wr_en = hsv_post_clken; 

wire [15:0] hsv_wr_data;
assign hsv_wr_data = (hsv_post_href && hsv_mask_vote) ? hsv_px_d3 : 16'h0000;


// ============================================================
// 6. 算法调度
// ============================================================

reg [5:0]   algo_sel_pclk1;
reg [5:0]   algo_sel_pclk2;

wire [3:0]  algo_pclk_num;
assign algo_pclk_num = algo_sel_pclk2[3:0];

// 只要串口指令一到，强制使用两级 D 触发器在两个时钟周期内无条件完成状态切换
always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin
        algo_sel_pclk1 <= 6'h3F;
        algo_sel_pclk2 <= 6'h3F;
    end else begin
        algo_sel_pclk1 <= algo_sel_async;
        algo_sel_pclk2 <= algo_sel_pclk1;
    end
end

wire        sdram_wr_req;
assign sdram_wr_req = (algo_pclk_num == 4'd1) ? he_valid :
                      (algo_pclk_num == 4'd5) ? morph_wr_en :
                      (algo_pclk_num == 4'd6) ? hsv_wr_en :
                      wr_en;

wire [15:0] sdram_wr_data;
assign sdram_wr_data = (algo_pclk_num == 4'd0) ? gray_rgb565 :
                       (algo_pclk_num == 4'd1) ? he_rgb565 :
                       (algo_pclk_num == 4'd5) ? morph_wr_data :
                       (algo_pclk_num == 4'd6) ? hsv_wr_data :
                       wr_data;

// ============================================================
// 7. 外设实例化与通信控制
// ============================================================

wire [15:0] rd_data_sdram;
wire        vga_rd_req;
wire [15:0] processed_rgb;
wire        uart_recv_done_fast;
wire        uart_recv_done_slow;
wire        uart_recv_done;

wire [7:0]  uart_recv_data_fast;
wire [7:0]  uart_recv_data_slow;
wire [7:0]  uart_recv_data;

wire        uart_send_en; 
wire [7:0]  uart_send_data;
wire        uart_tx_busy;

reg  [5:0]  algo_sel_sync1;
reg  [5:0]  algo_sel_sync2;
wire [5:0]  algo_sel_async;
wire [5:0]  algo_sel;

wire [15:0] rot_angle_any;
wire [15:0] rotate_data_out;

reg  [25:0] blink_cnt;
reg  [24:0] uart_seen_cnt; 
reg         uart_rxd_d0;
reg         uart_rxd_d1; 
reg  [24:0] uart_edge_cnt;

assign sys_init_done  = sdram_init_done & cfg_done;
assign ov5640_rst_n   = 1'b1; 
assign ov5640_pwdn    = 1'b0;
assign uart_recv_done = uart_recv_done_fast | uart_recv_done_slow;
assign uart_recv_data = uart_recv_done_fast ? uart_recv_data_fast : uart_recv_data_slow;

always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin 
        algo_sel_sync1 <= 6'h3F;
        algo_sel_sync2 <= 6'h3F; 
    end else begin 
        algo_sel_sync1 <= algo_sel_async; 
        algo_sel_sync2 <= algo_sel_sync1;
    end
end

assign algo_sel = algo_sel_sync2;

clk_gen clk_gen_inst (
    .areset(~sys_rst_n), 
    .inclk0(sys_clk), 
    .c0    (clk_100m), 
    .c1    (clk_100m_shift), 
    .c2    (clk_25m), 
    .c3    (ov5640_xclk), 
    .locked(locked)
);

ov5640_top ov5640_top_inst (
    .sys_clk        (clk_25m), 
    .sys_rst_n      (rst_n), 
    .sys_init_done  (sys_init_done),
    .ov5640_pclk    (ov5640_pclk), 
    .ov5640_href    (ov5640_href), 
    .ov5640_vsync   (ov5640_vsync), 
    .ov5640_data    (ov5640_data),
    .cfg_done       (cfg_done), 
    .sccb_scl       (sccb_scl), 
    .sccb_sda       (sccb_sda), 
    .ov5640_wr_en   (wr_en), 
    .ov5640_data_out(wr_data)
);

sdram_top sdram_top_inst (
    .sys_clk        (clk_100m), 
    .clk_out        (clk_100m_shift), 
    .sys_rst_n      (rst_n),
    .wr_fifo_wr_clk (ov5640_pclk), 
    .wr_fifo_wr_req (sdram_wr_req), 
    .wr_fifo_wr_data(sdram_wr_data),
    .sdram_wr_b_addr(24'd0), 
    .sdram_wr_e_addr(H_PIXEL * V_PIXEL), 
    .wr_burst_len   (WR_BURST_LEN), 
    .wr_rst         (~rst_n),
    .rd_fifo_rd_clk (clk_25m), 
    .rd_fifo_rd_req (vga_rd_req), 
    .sdram_rd_b_addr(24'd0), 
    .sdram_rd_e_addr(H_PIXEL * V_PIXEL),
    .rd_burst_len   (10'd512), 
    .rd_rst         (~rst_n),
    .rd_fifo_rd_data(rd_data_sdram), 
    .rd_fifo_num    (),
    .read_valid     (1'b1),
    .pingpang_en    (1'b1),
    .init_end       (sdram_init_done), 
    .sdram_clk      (sdram_clk), 
    .sdram_cke      (sdram_cke), 
    .sdram_cs_n     (sdram_cs_n),
    .sdram_ras_n    (sdram_ras_n), 
    .sdram_cas_n    (sdram_cas_n), 
    .sdram_we_n     (sdram_we_n), 
    .sdram_ba       (sdram_ba), 
    .sdram_addr     (sdram_addr), 
    .sdram_dqm      (),
    .sdram_dq       (sdram_dq)
);

uart_recv #(
    .CLK_FREQ(CLK_FREQ), 
    .UART_BPS(UART_BPS_FAST)
) u_uart_recv_fast (
    .sys_clk  (sys_clk), 
    .sys_rst_n(sys_rst_n), 
    .uart_rxd (uart_rxd), 
    .uart_done(uart_recv_done_fast), 
    .uart_data(uart_recv_data_fast)
);

uart_recv #(
    .CLK_FREQ(CLK_FREQ), 
    .UART_BPS(UART_BPS_SLOW)
) u_uart_recv_slow (
    .sys_clk  (sys_clk), 
    .sys_rst_n(sys_rst_n), 
    .uart_rxd (uart_rxd), 
    .uart_done(uart_recv_done_slow), 
    .uart_data(uart_recv_data_slow)
);

uart_send #(
    .CLK_FREQ(CLK_FREQ), 
    .UART_BPS(UART_BPS_FAST)
) u_uart_send (
    .sys_clk     (sys_clk), 
    .sys_rst_n   (sys_rst_n), 
    .uart_en     (uart_send_en), 
    .uart_din    (uart_send_data), 
    .uart_tx_busy(uart_tx_busy), 
    .uart_txd    (uart_txd)
);

uart_loop u_uart_loop (
    .sys_clk  (sys_clk), 
    .sys_rst_n(sys_rst_n), 
    .recv_done(uart_recv_done), 
    .recv_data(uart_recv_data), 
    .tx_busy  (uart_tx_busy), 
    .send_en  (uart_send_en), 
    .send_data(uart_send_data)
);

uart_cmd_decoder u_cmd_decoder (
    .clk          (sys_clk), 
    .rst_n        (sys_rst_n), 
    .uart_done    (uart_recv_done), 
    .uart_data    (uart_recv_data), 
    .algo_sel     (algo_sel_async), 
    .rot_angle_any(rot_angle_any)
);

img_rotate_any u_img_rotate_any (
    .clk       (clk_25m), 
    .rst_n     (rst_n), 
    .vsync     (vga_vs), 
    .vga_rd_req(vga_rd_req), 
    .din       (rd_data_sdram), 
    .angle     (rot_angle_any), 
    .dout      (rotate_data_out)
);

algo_mux u_algo_mux (
    .clk       (clk_25m), 
    .rst_n     (rst_n), 
    .vsync     (vga_vs), 
    .vga_rd_req(vga_rd_req), 
    .din       (rd_data_sdram), 
    .algo_sel  (algo_sel), 
    .rotate_din(rotate_data_out), 
    .dout      (processed_rgb)
);

wire [15:0] final_vga_data;
assign final_vga_data = (algo_sel[3:0] == 4'd4) ? rotate_data_out : processed_rgb;

vga_ctrl vga_ctrl_inst (
    .vga_clk     (clk_25m), 
    .sys_rst_n   (rst_n), 
    .pix_data    (final_vga_data), 
    .pix_data_req(vga_rd_req), 
    .hsync       (vga_hs), 
    .vsync       (vga_vs), 
    .rgb         (vga_rgb)
);

always @(posedge clk_25m or negedge rst_n) begin 
    if (!rst_n) begin
        blink_cnt <= 26'd0;
    end else begin
        blink_cnt <= blink_cnt + 1'b1;
    end
end

always @(posedge sys_clk or negedge sys_rst_n) begin 
    if (!sys_rst_n) begin
        uart_seen_cnt <= 25'd0;
    end else if (uart_recv_done) begin
        uart_seen_cnt <= {25{1'b1}};
    end else if (uart_seen_cnt != 25'd0) begin
        uart_seen_cnt <= uart_seen_cnt - 1'b1;
    end
end

always @(posedge sys_clk or negedge sys_rst_n) begin 
    if (!sys_rst_n) begin 
        uart_rxd_d0   <= 1'b1;
        uart_rxd_d1   <= 1'b1; 
        uart_edge_cnt <= 25'd0; 
    end else begin 
        uart_rxd_d0 <= uart_rxd;
        uart_rxd_d1 <= uart_rxd_d0; 
        if (uart_rxd_d0 ^ uart_rxd_d1) begin
            uart_edge_cnt <= {25{1'b1}};
        end else if (uart_edge_cnt != 25'd0) begin
            uart_edge_cnt <= uart_edge_cnt - 1'b1;
        end
    end 
end

assign LED3 = ((uart_seen_cnt != 25'd0) || (uart_edge_cnt != 25'd0)) ? 1'b1 : blink_cnt[25];

endmodule