`timescale 1ns/1ns
// =============================================================================
// 模块名：ov5640_vga_640x480  
// =============================================================================
module ov5640_vga_640x480 (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    // OV5640 摄像头接口
    input  wire        ov5640_pclk,
    input  wire        ov5640_vsync,
    input  wire        ov5640_href,
    input  wire [7:0]  ov5640_data,
    output wire        ov5640_rst_n,
    output wire        ov5640_pwdn,
    output wire        ov5640_xclk,
    output wire        sccb_scl,
    inout  wire        sccb_sda,

    // SDRAM 接口
    output wire        sdram_clk,
    output wire        sdram_cke,
    output wire        sdram_cs_n,
    output wire        sdram_ras_n,
    output wire        sdram_cas_n,
    output wire        sdram_we_n,
    output wire [1:0]  sdram_ba,
    output wire [12:0] sdram_addr,
    inout  wire [15:0] sdram_dq,

    // VGA 接口
    output wire        vga_hs,
    output wire        vga_vs,
    output wire [15:0] vga_rgb,

    // 串口接口
    input  wire        uart_rxd,     
    output wire        uart_txd,     

    // 阈值调节按键接口
    input  wire        key_inc,  
    input  wire        key_dec,      

    // 状态指示
    output wire        LED3          
);
// ============================================================
// 参数定义
// ============================================================
parameter H_PIXEL      = 24'd640;
parameter V_PIXEL      = 24'd480;
parameter WR_BURST_LEN = 10'd512;

parameter THRESH_HYST = 8'd12;
parameter [3:0] PRE_MAJ  = 4'd6;
parameter [3:0] POST_MAJ = 4'd5;

parameter CLK_FREQ   = 50_000_000;
parameter UART_BPS_FAST = 115200;
parameter UART_BPS_SLOW = 9600;

// ============================================================
// 内部信号声明
// ============================================================
wire        clk_100m;
wire        clk_100m_shift;
wire        clk_25m;
wire        locked;
wire        cfg_done;
wire        sdram_init_done;
wire        sys_init_done;
wire        wr_en;
wire [15:0] wr_data;

// ============================================================
// [算法 09] 图像去雾流水线（ov5640_pclk 域）
// ============================================================
wire        dehaze_vsync;
wire        dehaze_href;
wire        dehaze_en;
wire [15:0] dehaze_rgb565;
reg  [2:0]  dehaze_algo_d;

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin
        dehaze_algo_d <= 3'd0;
    end else begin
        dehaze_algo_d <= {dehaze_algo_d[1:0], (algo_sel_async[3:0] == 4'd9)};
    end
end
wire dehaze_srst_pclk;
assign dehaze_srst_pclk = dehaze_algo_d[1] & ~dehaze_algo_d[2];

Dehaze_YCbCr_Top #(
    .IMG_HDISP (11'd640),
    .IMG_VDISP (11'd480)
) u_dehaze (
    .clk        (ov5640_pclk      ),
    .rst_n      (rst_n            ),
    .srst       (dehaze_srst_pclk ),
    .in_vsync   (ov5640_vsync     ),
    .in_hsync   (ov5640_href      ),
    .in_de      (wr_en            ),
    .in_rgb565  (wr_data          ),
    .out_vsync  (dehaze_vsync     ),
    .out_hsync  (dehaze_href      ),
    .out_de     (dehaze_en        ),
    .out_rgb565 (dehaze_rgb565    )
);

// ============================================================
// [算法 0A] 图像卡通化流水线（ov5640_pclk 域） 
// ============================================================
wire        cartoon_vsync;
wire        cartoon_href;
wire        cartoon_en;
wire [15:0] cartoon_data;

Cartoon_Video_Processor #(
    .IMG_HDISP(H_PIXEL[9:0]),
    .IMG_VDISP(V_PIXEL[9:0])
) u_cartoon_processor (
    .clk               (ov5640_pclk),
    .rst_n             (rst_n),
    .cmos_frame_vsync  (ov5640_vsync),
    .cmos_frame_href   (ov5640_href),
    .cmos_frame_clken  (wr_en),
    .cmos_frame_data   (wr_data),
    .face_x_min        (), 
    .face_x_max        (),
    .face_y_min        (), 
    .face_y_max        (),
    .post_frame_vsync  (cartoon_vsync),
    .post_frame_href   (cartoon_href),
    .post_frame_clken  (cartoon_en),
    .post_img_data     (cartoon_data),
    .post_raw_data     () 
);

// ============================================================
// [算法 0B] 手势识别流水线（ov5640_pclk 域）
// ============================================================
wire skin_vsync;
wire skin_href;
wire skin_clken;
wire skin_bit;
wire [7:0]  img_r_w;
wire [7:0]  img_g_w;
wire [7:0]  img_b_w;

assign img_r_w = {wr_data[15:11], wr_data[15:13]};
assign img_g_w = {wr_data[10:5],  wr_data[10:9]};
assign img_b_w = {wr_data[4:0],   wr_data[4:2]};

skin_detect u_skin_detect (
    .clk             (ov5640_pclk),
    .rst_n           (rst_n),
    .i_r             (img_r_w),
    .i_g             (img_g_w),
    .i_b             (img_b_w),
    .i_vsync         (ov5640_vsync),
    .i_href          (ov5640_href),
    .i_clken         (wr_en),
    .post_frame_vsync(skin_vsync),
    .post_frame_href (skin_href),
    .post_frame_clken(skin_clken),
    .post_img_Bit    (skin_bit)
);

wire ges_erode_vsync;
wire ges_erode_href;
wire ges_erode_clken;
wire ges_erode_bit;

VIP_Bit_Erosion_Detector #(
    .IMG_HDISP(H_PIXEL[9:0]), 
    .IMG_VDISP(V_PIXEL[9:0])
) u_ges_erode (
    .clk             (ov5640_pclk), 
    .rst_n           (rst_n),
    .per_frame_vsync (skin_vsync), 
    .per_frame_href  (skin_href),
    .per_frame_clken (skin_clken), 
    .per_img_Bit     (skin_bit),
    .post_frame_vsync(ges_erode_vsync), 
    .post_frame_href (ges_erode_href),
    .post_frame_clken(ges_erode_clken), 
    .post_img_Bit    (ges_erode_bit)
);

wire ges_dilate_vsync;
wire ges_dilate_href;
wire ges_dilate_clken;
wire ges_dilate_bit;

VIP_Bit_Dilation_Detector #(
    .IMG_HDISP(H_PIXEL[9:0]), 
    .IMG_VDISP(V_PIXEL[9:0])
) u_ges_dilate (
    .clk             (ov5640_pclk), 
    .rst_n           (rst_n),
    .per_frame_vsync (ges_erode_vsync), 
    .per_frame_href  (ges_erode_href),
    .per_frame_clken (ges_erode_clken), 
    .per_img_Bit     (ges_erode_bit),
    .post_frame_vsync(ges_dilate_vsync), 
    .post_frame_href (ges_dilate_href),
    .post_frame_clken(ges_dilate_clken), 
    .post_img_Bit    (ges_dilate_bit)
);

wire [10:0] bbox_xmin;
wire [10:0] bbox_xmax;
wire [10:0] bbox_ymin;
wire [10:0] bbox_ymax;
wire        bbox_valid_sig;

bbox_detector #(
    .IMG_HDISP(H_PIXEL[9:0]), 
    .IMG_VDISP(V_PIXEL[9:0])
) u_ges_bbox (
    .clk             (ov5640_pclk), 
    .rst_n           (rst_n),
    .per_frame_vsync (ges_dilate_vsync), 
    .per_frame_href  (ges_dilate_href),
    .per_frame_clken (ges_dilate_clken), 
    .per_img_Bit     (ges_dilate_bit),
    .bbox_x_min      (bbox_xmin), 
    .bbox_x_max      (bbox_xmax), 
    .bbox_y_min      (bbox_ymin), 
    .bbox_y_max      (bbox_ymax), 
    .bbox_valid      (bbox_valid_sig)
);

wire [149:0] feature_vec;
wire         feat_valid_sig;

grid_feature #(
    .IMG_HDISP(H_PIXEL[9:0]), 
    .IMG_VDISP(V_PIXEL[9:0])
) u_ges_grid_feat (
    .clk             (ov5640_pclk), 
    .rst_n           (rst_n),
    .per_frame_vsync (ges_dilate_vsync), 
    .per_frame_href  (ges_dilate_href),
    .per_frame_clken (ges_dilate_clken), 
    .per_img_Bit     (ges_dilate_bit),
    .bbox_x_min      (bbox_xmin), 
    .bbox_x_max      (bbox_xmax), 
    .bbox_y_min      (bbox_ymin), 
    .bbox_y_max      (bbox_ymax), 
    .bbox_valid      (bbox_valid_sig),
    .feature_vec     (feature_vec), 
    .feat_valid      (feat_valid_sig)
);

wire [2:0] gesture_id;
wire       gesture_valid;
wire [7:0] best_score;

template_match u_ges_template (
    .clk             (ov5640_pclk), 
    .rst_n           (rst_n),
    .feature_vec     (feature_vec), 
    .feat_valid      (feat_valid_sig),
    .gesture_id      (gesture_id), 
    .gesture_valid   (gesture_valid), 
    .best_score      (best_score)
);

wire        ges_wr_en;
wire [15:0] ges_wr_data;

assign ges_wr_en   = ges_dilate_clken;
assign ges_wr_data = ges_dilate_bit ? 16'hFFFF : 16'h0000;

// ============================================================
// [算法 07/08] 图像双边/导引滤波（ov5640_pclk 域）
// ============================================================
wire [1:0] filter_mode;
assign filter_mode = (algo_sel_pclk2[3:0] == 4'd7) ? 2'b01 : 
                     (algo_sel_pclk2[3:0] == 4'd8) ? 2'b10 : 2'b00;

wire        filter_vs;
wire        filter_hs;
wire        filter_de;
wire [15:0] filter_rgb;

filter_top #(
    .IMG_WIDTH (H_PIXEL)
) u_filter_top_inst (
    .clk         (ov5640_pclk), 
    .rst_n       (rst_n), 
    .pix_data_en (wr_en), 
    .hsync_in    (ov5640_href), 
    .vsync_in    (ov5640_vsync), 
    .mode        (filter_mode), 
    .pix_data    (wr_data),
    .pix_out     (filter_rgb), 
    .hsync_out   (filter_hs), 
    .vsync_out   (filter_vs), 
    .data_en_out (filter_de)
);

// ============================================================
// algo_sel 跨域与写入端算法切换保护
// ============================================================
wire [15:0] rot_angle_async;
reg  [5:0]  algo_sel_pclk1;
reg  [5:0]  algo_sel_pclk2;
wire [3:0]  algo_pclk_num;

assign algo_pclk_num = algo_sel_pclk2[3:0];

wire current_de;
assign current_de = (algo_pclk_num == 4'd9) ? dehaze_en :
                    (algo_pclk_num == 4'd10)? cartoon_en :
                    (algo_pclk_num == 4'd11)? ges_wr_en  : 
                    (algo_pclk_num == 4'd7 || algo_pclk_num == 4'd8) ? filter_de :
                    wr_en;

reg [15:0] blank_cnt;

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin
        blank_cnt <= 16'd0;
    end else if (current_de) begin
        blank_cnt <= 16'd0;
    end else if (blank_cnt < 16'd5000) begin
        blank_cnt <= blank_cnt + 1'b1;
    end
end

always @(posedge ov5640_pclk or negedge rst_n) begin
    if (!rst_n) begin
        algo_sel_pclk1 <= 6'h3F;
        algo_sel_pclk2 <= 6'h3F;
    end else begin
        algo_sel_pclk1 <= algo_sel_async;
        if (blank_cnt == 16'd4000) begin
            algo_sel_pclk2 <= algo_sel_pclk1;
        end
    end
end

wire [7:0]  gray_r_w;
wire [7:0]  gray_g_w;
wire [7:0]  gray_b_w;
wire [7:0]  gray_y_w;
wire [15:0] gray_rgb565;

assign gray_r_w    = {wr_data[15:11], wr_data[15:13]};
assign gray_g_w    = {wr_data[10:5],  wr_data[10:9]};
assign gray_b_w    = {wr_data[4:0],   wr_data[4:2]};
assign gray_y_w    = (gray_r_w >> 2) + (gray_g_w >> 1) + (gray_b_w >> 2);
assign gray_rgb565 = {gray_y_w[7:3], gray_y_w[7:2], gray_y_w[7:3]};

// ============================================================
// SDRAM 写入端数据选择 MUX 
// ============================================================
wire        sdram_wr_req;
wire [15:0] sdram_wr_data;

assign sdram_wr_req  = current_de;
assign sdram_wr_data = (algo_pclk_num == 4'd0) ? gray_rgb565  :
                       (algo_pclk_num == 4'd9) ? dehaze_rgb565:
                       (algo_pclk_num == 4'd10)? cartoon_data :
                       (algo_pclk_num == 4'd11)? ges_wr_data  : 
                       (algo_pclk_num == 4'd7 || algo_pclk_num == 4'd8) ? filter_rgb :
                       wr_data;

// ============================================================
// 后续接口与系统连线
// ============================================================
wire [15:0] rd_data_sdram;
wire        vga_rd_req;
wire        rst_n;
wire        uart_recv_done_fast;
wire [7:0]  uart_recv_data_fast;
wire        uart_recv_done_slow;
wire [7:0]  uart_recv_data_slow;
wire        uart_recv_done;
wire [7:0]  uart_recv_data;
wire        uart_send_en;
wire [7:0]  uart_send_data;
wire        uart_tx_busy;

reg  [5:0]  algo_sel_sync1;
reg  [5:0]  algo_sel_sync2;
wire [5:0]  algo_sel_async;
wire [5:0]  algo_sel;

reg  [25:0] blink_cnt;
reg  [24:0] uart_seen_cnt;
reg         uart_rxd_d0;
reg         uart_rxd_d1;
reg  [24:0] uart_edge_cnt;

assign rst_n          = sys_rst_n & locked;
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

// 时钟生成（PLL）
clk_gen clk_gen_inst (
    .areset (~sys_rst_n),
    .inclk0 (sys_clk),
    .c0     (clk_100m),
    .c1     (clk_100m_shift),
    .c2     (clk_25m),
    .c3     (ov5640_xclk),
    .locked (locked)
);

// 摄像头配置与数据采集
ov5640_top ov5640_top_inst (
    .sys_clk         (clk_25m),
    .sys_rst_n       (rst_n),
    .sys_init_done   (sys_init_done),
    .ov5640_pclk     (ov5640_pclk),
    .ov5640_href     (ov5640_href),
    .ov5640_vsync    (ov5640_vsync),
    .ov5640_data     (ov5640_data),
    .cfg_done        (cfg_done),
    .sccb_scl        (sccb_scl),
    .sccb_sda        (sccb_sda),
    .ov5640_wr_en    (wr_en),
    .ov5640_data_out (wr_data)
);

// SDRAM 控制器
sdram_top sdram_top_inst (
    .sys_clk         (clk_100m),
    .clk_out         (clk_100m_shift),
    .sys_rst_n       (rst_n),
    .wr_fifo_wr_clk  (ov5640_pclk),
    .wr_fifo_wr_req  (sdram_wr_req),
    .wr_fifo_wr_data (sdram_wr_data),
    .sdram_wr_b_addr (24'd0),
    .sdram_wr_e_addr (H_PIXEL * V_PIXEL),
    .wr_burst_len    (WR_BURST_LEN),
    .wr_rst          (~rst_n),
    .rd_fifo_rd_clk  (clk_25m),
    .rd_fifo_rd_req  (vga_rd_req),
    .sdram_rd_b_addr (24'd0), 
    .sdram_rd_e_addr (H_PIXEL * V_PIXEL),
    .rd_burst_len    (10'd512),
    .rd_rst          (~rst_n),
    .rd_fifo_rd_data (rd_data_sdram),
    .rd_fifo_num     (),
    .read_valid      (1'b1),
    .pingpang_en     (1'b1),
    .init_end        (sdram_init_done),
    .sdram_clk       (sdram_clk),
    .sdram_cke       (sdram_cke),
    .sdram_cs_n      (sdram_cs_n),
    .sdram_ras_n     (sdram_ras_n),
    .sdram_cas_n     (sdram_cas_n),
    .sdram_we_n      (sdram_we_n),
    .sdram_ba        (sdram_ba),
    .sdram_addr      (sdram_addr),
    .sdram_dqm       (),
    .sdram_dq        (sdram_dq)
);

// 串口接收与发送模块
uart_recv #(.CLK_FREQ(CLK_FREQ), .UART_BPS(UART_BPS_FAST)) u_uart_recv_fast (
    .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .uart_rxd(uart_rxd),
    .uart_done(uart_recv_done_fast), .uart_data(uart_recv_data_fast)
);
uart_recv #(.CLK_FREQ(CLK_FREQ), .UART_BPS(UART_BPS_SLOW)) u_uart_recv_slow (
    .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .uart_rxd(uart_rxd),
    .uart_done(uart_recv_done_slow), .uart_data(uart_recv_data_slow)
);
uart_send #(.CLK_FREQ(CLK_FREQ), .UART_BPS(UART_BPS_FAST)) u_uart_send (
    .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .uart_en(uart_send_en),
    .uart_din(uart_send_data), .uart_tx_busy(uart_tx_busy), .uart_txd(uart_txd)
);
uart_loop u_uart_loop (
    .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .recv_done(uart_recv_done),
    .recv_data(uart_recv_data), .tx_busy(uart_tx_busy),
    .send_en(uart_send_en), .send_data(uart_send_data)
);
uart_cmd_decoder u_cmd_decoder (
    .clk           (sys_clk),
    .rst_n         (sys_rst_n),
    .uart_done     (uart_recv_done),
    .uart_data     (uart_recv_data),
    .algo_sel      (algo_sel_async),
    .rot_angle_any (rot_angle_async) 
);

// ============================================================
// VGA 控制器 (前端获取原生时序)
// ============================================================
wire        vga_hs_raw;
wire        vga_vs_raw;
wire [15:0] vga_rgb_raw;

vga_ctrl vga_ctrl_inst (
    .vga_clk      (clk_25m),
    .sys_rst_n    (rst_n),
    .pix_data     (rd_data_sdram), 
    .pix_data_req (vga_rd_req),
    .hsync        (vga_hs_raw),
    .vsync        (vga_vs_raw),
    .rgb          (vga_rgb_raw)
);

// ============================================================
// 读出端算法选择 帧同步防撕裂锁存
// ============================================================
reg vsync_d1_read;
reg vsync_d2_read;

always @(posedge clk_25m) begin
    vsync_d1_read <= vga_vs_raw;
    vsync_d2_read <= vsync_d1_read;
end

wire vsync_fall_read;
assign vsync_fall_read = vsync_d2_read & ~vsync_d1_read;

reg [5:0] active_algo_read;
always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
        active_algo_read <= 6'h3F;
    end else if (vsync_fall_read) begin
        active_algo_read <= algo_sel;
    end
end

// ============================================================
// [算法 13] 背景虚化流水线
// ============================================================
reg de_raw;
always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
        de_raw <= 1'b0;
    end else begin
        de_raw <= vga_rd_req;
    end
end

wire        pipe_valid;
wire        pipe_vs;
wire [15:0] pipe_data;
wire        filter_en;

assign filter_en = (active_algo_read == 6'd13);

image_pipeline u_image_pipeline (
    .clk        (clk_25m),
    .rst_n      (rst_n),
    .din_valid  (de_raw),
    .vs_in      (vga_vs_raw),
    .din        (vga_rgb_raw),
    .filter_en  (filter_en),
    .dout_valid (pipe_valid),
    .vs_out     (pipe_vs),
    .dout       (pipe_data)
);

// 匹配 10 拍延迟线
reg [9:0] hs_delay;
always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
        hs_delay <= 10'd0;
    end else begin
        hs_delay <= {hs_delay[8:0], vga_hs_raw};
    end
end
wire pipe_hs;
assign pipe_hs = hs_delay[9];

reg [9:0] de_delay;
always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
        de_delay <= 10'd0;
    end else begin
        de_delay <= {de_delay[8:0], vga_rd_req};
    end
end
wire pipe_de;
assign pipe_de = de_delay[9];

// ============================================================
// [算法 14] 面部磨皮美化流水线 (0x0E) 
// ============================================================
wire        beautify_hs;
wire        beautify_vs;
wire        beautify_de;
wire [15:0] beautify_data;
wire [1:0]  beautify_mode;

assign beautify_mode = (active_algo_read == 6'd14) ? 2'd1 : 2'd0;

img_proc #(
    .IMG_WIDTH  (H_PIXEL),
    .GUIDED_DLY (38)
) u_img_proc (
    .clk         (clk_25m),
    .rst_n       (rst_n),
    .iHSync      (vga_hs_raw),
    .iVSync      (vga_vs_raw),
    .iDataEnable (de_raw),     
    .iRGB565     (vga_rgb_raw),
    .mode_sel    (beautify_mode),
    .oHSync      (beautify_hs),
    .oVSync      (beautify_vs),
    .oDataEnable (beautify_de),
    .oRGB565     (beautify_data)
);

// ============================================================
// 读出端算法数据流与时序通道安全 MUX
// ============================================================
wire        is_beautify;
assign is_beautify = (active_algo_read == 6'd14);

wire        sync_hs;
wire        sync_vs;
wire        sync_de;
wire [15:0] sync_data;

assign sync_hs   = is_beautify ? beautify_hs   : pipe_hs;
assign sync_vs   = is_beautify ? beautify_vs   : pipe_vs;
assign sync_de   = is_beautify ? beautify_de   : pipe_de;
assign sync_data = is_beautify ? beautify_data : pipe_data;

// ============================================================
// 算法多路选择器 
// ============================================================
wire [15:0] processed_rgb;

algo_mux u_algo_mux (
    .clk        (clk_25m),
    .rst_n      (rst_n),
    .vsync      (sync_vs),
    .vga_rd_req (sync_de),     
    .din        (sync_data),      
    .algo_sel   (algo_sel), 
    .dout       (processed_rgb)
);

reg final_hs;
reg final_vs;
reg final_de;

always @(posedge clk_25m or negedge rst_n) begin
    if (!rst_n) begin
        final_hs <= 1'b0;
        final_vs <= 1'b0;
        final_de <= 1'b0;
    end else begin
        final_hs <= sync_hs;
        final_vs <= sync_vs;
        final_de <= sync_de;
    end
end

assign vga_hs  = final_hs;
assign vga_vs  = final_vs;
assign vga_rgb = final_de ? processed_rgb : 16'd0;

// 心跳指示灯与状态检测
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