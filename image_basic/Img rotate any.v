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
// 1. 场同步检测
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

// ─────────────────────────────────────────────────────────────
// 2. cos/sin ROM IP 例化 
// ─────────────────────────────────────────────────────────────
wire signed [15:0] cos_val_rom;
wire signed [15:0] sin_val_rom;
cos_table u_cos_table (
    .address (angle[8:0]), 
    .clock   (clk),
    .data    (16'd0),
    .wren    (1'b0),
    .q       (cos_val_rom)
);
sin_table u_sin_table (
    .address (angle[8:0]), 
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
// 3. VGA 物理坐标追踪
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
// 4. 写地址与灰度转换流水线 (降采样一半存入 320x240 BRAM)
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

wire wr_en = req_d1 && (req_x_d1[0] == 0) && (req_y_d1[0] == 0);

// ─────────────────────────────────────────────────────────────
// 5. 读地址：锚定屏幕物理中心(320, 240)，以旋转后的坐标为偏移进行仿射变换逆映射
// ─────────────────────────────────────────────────────────────
wire signed [12:0] screen_x = $signed({3'b000, req_x});
wire signed [12:0] screen_y = $signed({3'b000, req_y});
wire signed [12:0] dx = screen_x - 13'sd320;
wire signed [12:0] dy = screen_y - 13'sd240;

wire signed [28:0] dx_cos = dx * frame_cos;
wire signed [28:0] dy_sin = dy * frame_sin;
wire signed [28:0] dx_sin = dx * frame_sin;
wire signed [28:0] dy_cos = dy * frame_cos;

wire signed [29:0] rot_x_full = dx_cos + dy_sin;
wire signed [29:0] rot_y_full = dy_cos - dx_sin;

wire signed [14:0] rot_x = rot_x_full >>> 15;
wire signed [14:0] rot_y = rot_y_full >>> 15;

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

reg        valid_pixel_d1;
always @(posedge clk) begin
    valid_pixel_d1 <= valid_rd;
end

// ─────────────────────────────────────────────────────────────
// 6. 4-Bank 单帧缓冲阵列 
// ─────────────────────────────────────────────────────────────
wire [14:0] wr_word = wr_idx[16:2];
wire [1:0]  wr_byte = wr_idx[1:0];

(* ram_style = "block" *) reg [7:0] bank0 [0:19455];
(* ram_style = "block" *) reg [7:0] bank1 [0:19455];
(* ram_style = "block" *) reg [7:0] bank2 [0:19455];
(* ram_style = "block" *) reg [7:0] bank3 [0:19455];

always @(posedge clk) begin
    if (wr_en) begin
        case (wr_byte)
            2'd0: bank0[wr_word] <= gray_pixel;
            2'd1: bank1[wr_word] <= gray_pixel;
            2'd2: bank2[wr_word] <= gray_pixel;
            2'd3: bank3[wr_word] <= gray_pixel;
        endcase
    end
end

wire [14:0] rd_word = clamped_rd_idx[16:2];
wire [1:0]  rd_byte = clamped_rd_idx[1:0];

reg [1:0] rd_byte_d1;
reg [7:0] q0, q1, q2, q3;

always @(posedge clk) begin
    rd_byte_d1 <= rd_byte;
    q0 <= bank0[rd_word];
    q1 <= bank1[rd_word];
    q2 <= bank2[rd_word];
    q3 <= bank3[rd_word];
end

reg [7:0] rd_data;
always @(*) begin
    case (rd_byte_d1)
        2'd0: rd_data = q0;
        2'd1: rd_data = q1;
        2'd2: rd_data = q2;
        2'd3: rd_data = q3;
    endcase
end

// 同步透传的 din 信号
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