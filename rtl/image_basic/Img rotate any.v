`timescale 1ns/1ns
// =============================================================================
//  img_rotate_any.v   ——   实时任意角度灰度图像旋转 
// =============================================================================

module img_rotate_any (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        vga_rd_req,
    input  wire [15:0] din,
    input  wire [15:0] angle,
    output reg  [15:0] dout
);

// ─────────────────────────────────────────────────────────────
// 1. 场同步检测与双缓冲页面翻转
// ─────────────────────────────────────────────────────────────
reg vsync_d1, vsync_d2;
always @(posedge clk) begin
    vsync_d1 <= vsync;
    vsync_d2 <= vsync_d1;
end
wire vsync_rise = vsync_d1 & ~vsync_d2;
wire vsync_fall = vsync_d2 & ~vsync_d1;

reg vsync_rise_d1, vsync_rise_d2;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vsync_rise_d1 <= 1'b0;
        vsync_rise_d2 <= 1'b0;
    end else begin
        vsync_rise_d1 <= vsync_rise;
        vsync_rise_d2 <= vsync_rise_d1;
    end
end

reg wr_page;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) wr_page <= 1'b0;
    else if (vsync_rise) wr_page <= ~wr_page;
end
wire rd_page = ~wr_page;

// ─────────────────────────────────────────────────────────────
// 2. cos/sin ROM IP 例化
// ─────────────────────────────────────────────────────────────
wire signed [15:0] cos_val_rom;
wire signed [15:0] sin_val_rom;

cos_table u_cos_table (
    .address (angle[15:7]),
    .clock   (clk),
    .data    (16'd0),
    .wren    (1'b0),
    .q       (cos_val_rom)
);

sin_table u_sin_table (
    .address (angle[15:7]),
    .clock   (clk),
    .data    (16'd0),
    .wren    (1'b0),
    .q       (sin_val_rom)
);

reg signed [15:0] frame_cos, frame_sin;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_cos <= 16'sh7FFF;
        frame_sin <= 16'sh0000;
    end else if (vsync_rise_d2) begin
        frame_cos <= cos_val_rom;
        frame_sin <= sin_val_rom;
    end
end

// ─────────────────────────────────────────────────────────────
// 3.VGA 物理坐标追踪
// ─────────────────────────────────────────────────────────────
reg [9:0] req_x, req_y;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        req_x <= 0;
        req_y <= 0;
    end else if (vsync_fall) begin
        req_x <= 0;
        req_y <= 0;
    end else if (vga_rd_req) begin
        if (req_x == 640 - 1) begin
            req_x <= 0;
            if (req_y == 480 - 1) req_y <= 0;
            else req_y <= req_y + 1;
        end else begin
            req_x <= req_x + 1;
        end
    end
end

// ─────────────────────────────────────────────────────────────
// 4. 写地址与灰度转换流水线
// ─────────────────────────────────────────────────────────────
reg        req_d1;
reg [9:0]  req_x_d1, req_y_d1;
always @(posedge clk) begin
    req_d1   <= vga_rd_req;
    req_x_d1 <= req_x;
    req_y_d1 <= req_y;
end

wire [7:0] r8 = {din[15:11], din[13:11]}; 
wire [7:0] g8 = {din[10:5],  din[6:5]};
wire [7:0] b8 = {din[4:0],   din[2:0]};   
wire [15:0] r16 = r8;
wire [15:0] g16 = g8;
wire [15:0] b16 = b8;

wire [15:0] gray_sum = (r16 * 16'd77) + (g16 * 16'd150) + (b16 * 16'd29);
wire [7:0]  gray_pixel = gray_sum[15:8];

// 降采样一倍
wire [8:0] wr_x = req_x_d1 >> 1;
wire [8:0] wr_y = req_y_d1 >> 1;
wire [16:0] ext_wr_x = {8'd0, wr_x};
wire [16:0] ext_wr_y = {8'd0, wr_y};
wire [16:0] wr_idx = (ext_wr_y << 8) + (ext_wr_y << 6) + ext_wr_x;

wire [4:0]  wr_bank   = wr_idx[16:12];
wire [11:0] wr_offset = wr_idx[11:0];
wire [5:0]  wr_bk     = wr_page ? ({1'b0, wr_bank} + 6'd19) : {1'b0, wr_bank};
wire wr_en = req_d1 && (req_x_d1[0] == 0) && (req_y_d1[0] == 0);

// ─────────────────────────────────────────────────────────────
// 5. 读地址
// ─────────────────────────────────────────────────────────────

// [步骤1]：以屏幕中心(320, 240)为数学原点，求当前扫描点的偏移
wire signed [12:0] screen_x = $signed({3'b000, req_x});
wire signed [12:0] screen_y = $signed({3'b000, req_y});

wire signed [12:0] dx = screen_x - 13'sd320;
wire signed [12:0] dy = screen_y - 13'sd240;

// [步骤2]：直接与 Q1.15 的 ROM 值进行乘法
wire signed [28:0] dx_cos = dx * frame_cos;
wire signed [28:0] dy_sin = dy * frame_sin;
wire signed [28:0] dx_sin = dx * frame_sin;
wire signed [28:0] dy_cos = dy * frame_cos;

// [步骤3]：完成坐标旋转矩阵计算 
wire signed [29:0] rot_x_full = dx_cos + dy_sin;
wire signed [29:0] rot_y_full = dy_cos - dx_sin;

// [步骤4]：算术右移 15 位还原真实坐标 
wire signed [14:0] rot_x = rot_x_full >>> 15;
wire signed [14:0] rot_y = rot_y_full >>> 15;

// [步骤5]：平移回 320x240 小图 BRAM 的逻辑中心 (160, 120)
wire signed [14:0] src_x_s = rot_x + 15'sd160;
wire signed [14:0] src_y_s = rot_y + 15'sd120;

wire valid_rd = (src_x_s >= 15'sd0) && (src_x_s < 15'sd320) &&
                (src_y_s >= 15'sd0) && (src_y_s < 15'sd240);

wire [8:0]  src_x  = src_x_s[8:0];
wire [8:0]  src_y  = src_y_s[8:0];

wire [16:0] ext_rd_x = {8'd0, src_x};
wire [16:0] ext_rd_y = {8'd0, src_y};
wire [16:0] rd_idx = (ext_rd_y << 8) + (ext_rd_y << 6) + ext_rd_x;
wire [16:0] clamped_rd_idx = (rd_idx > 17'd76799) ? 17'd76799 : rd_idx;

wire [4:0]  rd_bank   = clamped_rd_idx[16:12];
wire [11:0] rd_offset = clamped_rd_idx[11:0];
wire [5:0]  rd_bk     = rd_page ? ({1'b0, rd_bank} + 6'd19) : {1'b0, rd_bank};

reg [5:0]  use_rd_bk;
reg        valid_pixel_d1;
always @(posedge clk) begin
    use_rd_bk      <= rd_bk;      
    valid_pixel_d1 <= valid_rd;
end

// ─────────────────────────────────────────────────────────────
// 6. 38-Bank 双帧 Ping-Pong BRAM 阵列 (8位宽)
// ─────────────────────────────────────────────────────────────
(* ram_style = "block" *) reg [7:0] bank00 [0:4095];
(* ram_style = "block" *) reg [7:0] bank01 [0:4095];
(* ram_style = "block" *) reg [7:0] bank02 [0:4095];
(* ram_style = "block" *) reg [7:0] bank03 [0:4095];
(* ram_style = "block" *) reg [7:0] bank04 [0:4095];
(* ram_style = "block" *) reg [7:0] bank05 [0:4095];
(* ram_style = "block" *) reg [7:0] bank06 [0:4095];
(* ram_style = "block" *) reg [7:0] bank07 [0:4095];
(* ram_style = "block" *) reg [7:0] bank08 [0:4095];
(* ram_style = "block" *) reg [7:0] bank09 [0:4095];
(* ram_style = "block" *) reg [7:0] bank10 [0:4095];
(* ram_style = "block" *) reg [7:0] bank11 [0:4095];
(* ram_style = "block" *) reg [7:0] bank12 [0:4095];
(* ram_style = "block" *) reg [7:0] bank13 [0:4095];
(* ram_style = "block" *) reg [7:0] bank14 [0:4095];
(* ram_style = "block" *) reg [7:0] bank15 [0:4095];
(* ram_style = "block" *) reg [7:0] bank16 [0:4095];
(* ram_style = "block" *) reg [7:0] bank17 [0:4095];
(* ram_style = "block" *) reg [7:0] bank18 [0:4095];
(* ram_style = "block" *) reg [7:0] bank19 [0:4095];
(* ram_style = "block" *) reg [7:0] bank20 [0:4095];
(* ram_style = "block" *) reg [7:0] bank21 [0:4095];
(* ram_style = "block" *) reg [7:0] bank22 [0:4095];
(* ram_style = "block" *) reg [7:0] bank23 [0:4095];
(* ram_style = "block" *) reg [7:0] bank24 [0:4095];
(* ram_style = "block" *) reg [7:0] bank25 [0:4095];
(* ram_style = "block" *) reg [7:0] bank26 [0:4095];
(* ram_style = "block" *) reg [7:0] bank27 [0:4095];
(* ram_style = "block" *) reg [7:0] bank28 [0:4095];
(* ram_style = "block" *) reg [7:0] bank29 [0:4095];
(* ram_style = "block" *) reg [7:0] bank30 [0:4095];
(* ram_style = "block" *) reg [7:0] bank31 [0:4095];
(* ram_style = "block" *) reg [7:0] bank32 [0:4095];
(* ram_style = "block" *) reg [7:0] bank33 [0:4095];
(* ram_style = "block" *) reg [7:0] bank34 [0:4095];
(* ram_style = "block" *) reg [7:0] bank35 [0:4095];
(* ram_style = "block" *) reg [7:0] bank36 [0:4095];
(* ram_style = "block" *) reg [7:0] bank37 [0:4095];

always @(posedge clk) begin
    if (wr_en) begin
        case (wr_bk)
            6'd00: bank00[wr_offset] <= gray_pixel;
            6'd01: bank01[wr_offset] <= gray_pixel;
            6'd02: bank02[wr_offset] <= gray_pixel;
            6'd03: bank03[wr_offset] <= gray_pixel;
            6'd04: bank04[wr_offset] <= gray_pixel;
            6'd05: bank05[wr_offset] <= gray_pixel;
            6'd06: bank06[wr_offset] <= gray_pixel;
            6'd07: bank07[wr_offset] <= gray_pixel;
            6'd08: bank08[wr_offset] <= gray_pixel;
            6'd09: bank09[wr_offset] <= gray_pixel;
            6'd10: bank10[wr_offset] <= gray_pixel;
            6'd11: bank11[wr_offset] <= gray_pixel;
            6'd12: bank12[wr_offset] <= gray_pixel;
            6'd13: bank13[wr_offset] <= gray_pixel;
            6'd14: bank14[wr_offset] <= gray_pixel;
            6'd15: bank15[wr_offset] <= gray_pixel;
            6'd16: bank16[wr_offset] <= gray_pixel;
            6'd17: bank17[wr_offset] <= gray_pixel;
            6'd18: bank18[wr_offset] <= gray_pixel;
            6'd19: bank19[wr_offset] <= gray_pixel;
            6'd20: bank20[wr_offset] <= gray_pixel;
            6'd21: bank21[wr_offset] <= gray_pixel;
            6'd22: bank22[wr_offset] <= gray_pixel;
            6'd23: bank23[wr_offset] <= gray_pixel;
            6'd24: bank24[wr_offset] <= gray_pixel;
            6'd25: bank25[wr_offset] <= gray_pixel;
            6'd26: bank26[wr_offset] <= gray_pixel;
            6'd27: bank27[wr_offset] <= gray_pixel;
            6'd28: bank28[wr_offset] <= gray_pixel;
            6'd29: bank29[wr_offset] <= gray_pixel;
            6'd30: bank30[wr_offset] <= gray_pixel;
            6'd31: bank31[wr_offset] <= gray_pixel;
            6'd32: bank32[wr_offset] <= gray_pixel;
            6'd33: bank33[wr_offset] <= gray_pixel;
            6'd34: bank34[wr_offset] <= gray_pixel;
            6'd35: bank35[wr_offset] <= gray_pixel;
            6'd36: bank36[wr_offset] <= gray_pixel;
            6'd37: bank37[wr_offset] <= gray_pixel;
            default: ;
        endcase
    end
end

reg [7:0] q00, q01, q02, q03, q04, q05, q06, q07, q08, q09;
reg [7:0] q10, q11, q12, q13, q14, q15, q16, q17, q18, q19;
reg [7:0] q20, q21, q22, q23, q24, q25, q26, q27, q28, q29;
reg [7:0] q30, q31, q32, q33, q34, q35, q36, q37;

always @(posedge clk) begin
    q00 <= bank00[rd_offset]; q01 <= bank01[rd_offset];
    q02 <= bank02[rd_offset]; q03 <= bank03[rd_offset];
    q04 <= bank04[rd_offset]; q05 <= bank05[rd_offset];
    q06 <= bank06[rd_offset]; q07 <= bank07[rd_offset];
    q08 <= bank08[rd_offset]; q09 <= bank09[rd_offset];
    q10 <= bank10[rd_offset]; q11 <= bank11[rd_offset];
    q12 <= bank12[rd_offset]; q13 <= bank13[rd_offset];
    q14 <= bank14[rd_offset]; q15 <= bank15[rd_offset];
    q16 <= bank16[rd_offset]; q17 <= bank17[rd_offset];
    q18 <= bank18[rd_offset]; q19 <= bank19[rd_offset];
    q20 <= bank20[rd_offset]; q21 <= bank21[rd_offset];
    q22 <= bank22[rd_offset]; q23 <= bank23[rd_offset];
    q24 <= bank24[rd_offset]; q25 <= bank25[rd_offset];
    q26 <= bank26[rd_offset]; q27 <= bank27[rd_offset];
    q28 <= bank28[rd_offset]; q29 <= bank29[rd_offset];
    q30 <= bank30[rd_offset]; q31 <= bank31[rd_offset];
    q32 <= bank32[rd_offset]; q33 <= bank33[rd_offset];
    q34 <= bank34[rd_offset]; q35 <= bank35[rd_offset];
    q36 <= bank36[rd_offset]; q37 <= bank37[rd_offset];
end

reg [7:0] rd_data;
always @(*) begin
    case (use_rd_bk)
        6'd00: rd_data = q00; 6'd01: rd_data = q01;
        6'd02: rd_data = q02; 6'd03: rd_data = q03;
        6'd04: rd_data = q04; 6'd05: rd_data = q05;
        6'd06: rd_data = q06; 6'd07: rd_data = q07;
        6'd08: rd_data = q08; 6'd09: rd_data = q09;
        6'd10: rd_data = q10; 6'd11: rd_data = q11;
        6'd12: rd_data = q12; 6'd13: rd_data = q13;
        6'd14: rd_data = q14; 6'd15: rd_data = q15;
        6'd16: rd_data = q16; 6'd17: rd_data = q17;
        6'd18: rd_data = q18; 6'd19: rd_data = q19;
        6'd20: rd_data = q20; 6'd21: rd_data = q21;
        6'd22: rd_data = q22; 6'd23: rd_data = q23;
        6'd24: rd_data = q24; 6'd25: rd_data = q25;
        6'd26: rd_data = q26; 6'd27: rd_data = q27;
        6'd28: rd_data = q28; 6'd29: rd_data = q29;
        6'd30: rd_data = q30; 6'd31: rd_data = q31;
        6'd32: rd_data = q32; 6'd33: rd_data = q33;
        6'd34: rd_data = q34; 6'd35: rd_data = q35;
        6'd36: rd_data = q36; 6'd37: rd_data = q37;
        default: rd_data = 8'd0;
    endcase
end

reg [15:0] din_d1, din_d2;
always @(posedge clk) begin
    din_d1 <= din;
    din_d2 <= din_d1;
end

// ─────────────────────────────────────────────────────────────
// 7. 最终输出
// ─────────────────────────────────────────────────────────────
always @(posedge clk) begin
    if (angle == 16'd0) begin
        dout <= din_d2; 
    end else if (valid_pixel_d1) begin
        dout <= {rd_data[7:3], rd_data[7:2], rd_data[7:3]};
    end else begin
        dout <= 16'h0000; 
    end
end

endmodule