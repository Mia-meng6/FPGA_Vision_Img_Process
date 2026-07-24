`timescale 1ns/1ps
// =============================================================================
// Module  : filter_top
// Purpose : 滤波模块总路
// =============================================================================
module filter_top #(
    parameter   IMG_WIDTH = 640
) (
    input   wire            clk, 
    input   wire            rst_n, 
    input   wire            pix_data_en, 
    input   wire            hsync_in, 
    input   wire            vsync_in, 
    input   wire    [1:0]   mode, 
    input   wire    [15:0]  pix_data,
    
    output  wire    [15:0]  pix_out, 
    output  wire            hsync_out, 
    output  wire            vsync_out, 
    output  wire            data_en_out
);

    // ============================================================
    // 1. 帧边界锁存逻辑 (mode_latched) 
    // ============================================================
    reg [1:0] mode_latched;
    reg       vsync_in_d1;
    always @(posedge clk) vsync_in_d1 <= vsync_in;
    wire vsync_edge = vsync_in ^ vsync_in_d1; 
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mode_latched <= 2'b00;
        else if (vsync_edge) mode_latched <= mode;
    end

    // ============================================================
    // 2. 颜色空间转换 (RGB -> YCbCr)
    // ============================================================
    wire [7:0] r_in = {pix_data[15:11], pix_data[15:13]};
    wire [7:0] g_in = {pix_data[10:5],  pix_data[10:9]};
    wire [7:0] b_in = {pix_data[4:0],   pix_data[4:2]};
    wire [7:0] yuv_y, yuv_cb, yuv_cr;
    wire       yuv_hs, yuv_vs, yuv_de;

    rgb_to_ycbcr u_rgb2yuv (
        .clk(clk), .i_r_8b(r_in), .i_g_8b(g_in), .i_b_8b(b_in), 
        .i_h_sync(hsync_in), .i_v_sync(vsync_in), .i_data_en(pix_data_en), 
        .o_y_8b(yuv_y), .o_cb_8b(yuv_cb), .o_cr_8b(yuv_cr), 
        .o_h_sync(yuv_hs), .o_v_sync(yuv_vs), .o_data_en(yuv_de)
    );

    // ============================================================
    // 3. 算法后台热运行 
    // ============================================================
    wire [7:0] bil_y, gui_y;   
    wire       bil_hs, bil_vs, bil_de, gui_hs, gui_vs, gui_de;

    bilateral_filter #( .IMG_WIDTH (IMG_WIDTH) ) u_bil (
        .clk(clk), .rst_n(rst_n), .iHSync(yuv_hs), .iVSync(yuv_vs), 
        .iDataEnable(yuv_de), .iData(yuv_y), 
        .oHSync(bil_hs), .oVSync(bil_vs), .oDataEnable(bil_de), .oData(bil_y)
    );

    guided_filter #( .IMG_WIDTH (IMG_WIDTH) ) u_gui (
        .clk(clk), .rst_n(rst_n), .iHSync(yuv_hs), .iVSync(yuv_vs), 
        .iDataEnable(yuv_de), .iData(yuv_y), 
        .oHSync(gui_hs), .oVSync(gui_vs), .oDataEnable(gui_de), .oData(gui_y)
    );

    // ============================================================
    // 4. 色差补偿与模式 MUX
    // ============================================================
    reg [7:0] cb_d_bil [0:29]; reg [7:0] cr_d_bil [0:29];
    reg [7:0] cb_d_gui [0:37]; reg [7:0] cr_d_gui [0:37]; 
    integer i, j;
    
    always @(posedge clk) begin
        cb_d_bil[0] <= yuv_cb; cr_d_bil[0] <= yuv_cr;
        for(i = 1; i <= 29; i = i + 1) begin 
            cb_d_bil[i] <= cb_d_bil[i-1]; cr_d_bil[i] <= cr_d_bil[i-1]; 
        end
        cb_d_gui[0] <= yuv_cb; cr_d_gui[0] <= yuv_cr; 
        for(j = 1; j <= 37; j = j + 1) begin 
            cb_d_gui[j] <= cb_d_gui[j-1]; cr_d_gui[j] <= cr_d_gui[j-1]; 
        end
    end

    reg [7:0] f_y, f_cb, f_cr;
    reg       f_hs, f_vs, f_de;
    always @(*) begin
        case(mode_latched)
            2'b01: begin 
                f_y = bil_y; f_hs = bil_hs; f_vs = bil_vs; f_de = bil_de; 
                f_cb = cb_d_bil[29]; f_cr = cr_d_bil[29];
            end
            2'b10: begin 
                f_y = gui_y; f_hs = gui_hs; f_vs = gui_vs; f_de = gui_de; 
                f_cb = cb_d_gui[37]; f_cr = cr_d_gui[37];
            end
            default: begin 
                f_y = yuv_y; f_hs = yuv_hs; f_vs = yuv_vs; f_de = yuv_de; 
                f_cb = yuv_cb; f_cr = yuv_cr;
            end
        endcase
    end

    // ============================================================
    // 5. 颜色空间反转 (YCbCr -> RGB) 
    // ============================================================
    wire [7:0] or8, og8, ob8;
    wire       ohs, ovs, ode;
    ycbcr_to_rgb u_yuv2rgb (
        .clk(clk), .i_y_8b(f_y), .i_cb_8b(f_cb), .i_cr_8b(f_cr), 
        .i_h_sync(f_hs), .i_v_sync(f_vs), .i_data_en(f_de), 
        .o_r_8b(or8), .o_g_8b(og8), .o_b_8b(ob8), 
        .o_h_sync(ohs), .o_v_sync(ovs), .o_data_en(ode)
    );

    reg [15:0] rgb_o [0:38];
    reg hs_o [0:38], vs_o [0:38], de_o [0:38]; 
    integer k;
    always @(posedge clk) begin
        rgb_o[0] <= {or8[7:3], og8[7:2], ob8[7:3]}; 
        hs_o[0] <= ohs; vs_o[0] <= ovs; de_o[0] <= ode;
        for(k = 1; k <= 38; k = k + 1) begin 
            rgb_o[k] <= rgb_o[k-1]; hs_o[k] <= hs_o[k-1]; 
            vs_o[k] <= vs_o[k-1]; de_o[k] <= de_o[k-1];
        end
    end
    
    wire final_hs_w = (mode_latched == 2'b10) ? hs_o[0]  : ((mode_latched == 2'b01) ? hs_o[8] : hs_o[38]);
    wire final_vs_w = (mode_latched == 2'b10) ? vs_o[0]  : ((mode_latched == 2'b01) ? vs_o[8] : vs_o[38]);
    wire final_de_w = (mode_latched == 2'b10) ? de_o[0]  : ((mode_latched == 2'b01) ? de_o[8] : de_o[38]);
    wire [15:0] active_pix = (mode_latched == 2'b10) ? rgb_o[0] : ((mode_latched == 2'b01) ? rgb_o[8] : rgb_o[38]);

    // ============================================================
    // 6. 空间相位对齐
    // ============================================================
    wire [11:0] shift_offset = (mode_latched == 2'b10) ? 12'd1284 : 
                               (mode_latched == 2'b01) ? 12'd642  : 12'd0;

    reg [18:0] in_de_cnt;
    reg [11:0] pad_cnt;
    reg        padding_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_de_cnt      <= 19'd0;
            pad_cnt        <= 12'd0;
            padding_active <= 1'b0;
        end else begin
            // 场消隐期强制复位
            if (vsync_edge && !padding_active) begin
                in_de_cnt <= 19'd0;
                pad_cnt   <= 12'd0;
            end
            
            if (final_de_w) begin
                if (in_de_cnt == 19'd307199) begin
                    in_de_cnt <= 19'd0; // 计满一帧真实像素，停止接收
                    if (shift_offset > 12'd0) begin
                        padding_active <= 1'b1; 
                    end
                end else begin
                    in_de_cnt <= in_de_cnt + 1'b1;
                end
            end
            
            if (padding_active) begin
                if (pad_cnt == shift_offset - 1'b1) begin
                    padding_active <= 1'b0; 
                    pad_cnt <= 12'd0;
                end else begin
                    pad_cnt <= pad_cnt + 1'b1;
                end
            end
        end
    end

    wire aligned_de = (final_de_w && (in_de_cnt >= shift_offset)) || padding_active;
    wire [15:0] aligned_pix = padding_active ? 16'd0 : active_pix; 

    reg [15:0] out_rgb_r;
    reg        out_hs_r, out_vs_r, out_de_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            out_hs_r  <= 1'b1; out_vs_r  <= 1'b1; 
            out_de_r  <= 1'b0; out_rgb_r <= 16'd0;
        end else begin 
            out_hs_r  <= final_hs_w; out_vs_r  <= final_vs_w; 
            out_de_r  <= aligned_de; out_rgb_r <= aligned_de ? aligned_pix : 16'd0;
        end
    end

    assign hsync_out = out_hs_r; assign vsync_out = out_vs_r;
    assign data_en_out = out_de_r; assign pix_out = out_rgb_r;
endmodule