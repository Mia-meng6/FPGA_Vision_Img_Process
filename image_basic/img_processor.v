`timescale 1ns/1ns

module img_processor (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        vga_rd_req,
    input  wire [15:0] din,
    input  wire [1:0]  mode,
    output reg  [15:0] dout
);

localparam MODE_ORIG     = 2'd0;
localparam MODE_ZOOM_IN  = 2'd1;
localparam MODE_ZOOM_OUT = 2'd2;

// ==========================================
// 1. 场同步下降沿检测 
// ==========================================
reg vsync_d1, vsync_d2;
always @(posedge clk) begin
    vsync_d1 <= vsync;
    vsync_d2 <= vsync_d1;
end
wire vsync_fall = vsync_d2 & ~vsync_d1;

reg [1:0] active_mode;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) active_mode <= MODE_ORIG;
    else if (vsync_fall) active_mode <= mode; 
end

// ==========================================
// 2. VGA 物理坐标追踪 
// ==========================================
reg [9:0] req_x, req_y;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        req_x <= 0; req_y <= 0;
    end else if (vsync_fall) begin
        req_x <= 0; req_y <= 0;
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

// ==========================================
// 3. BRAM 读逻辑 
// ==========================================
reg [9:0] read_y, read_x;
reg       use_fb;

always @(*) begin
    use_fb = 1'b0;
    read_y = 10'd0; 
    read_x = 10'd0;
    
    if (active_mode == MODE_ZOOM_IN) begin
        // 放大模式
        read_y = req_y >> 1;
        read_x = req_x >> 1;
        use_fb = 1'b1;
    end else if (active_mode == MODE_ZOOM_OUT) begin
        // 缩小模式
        if (req_x >= 160 && req_x < 480 && req_y >= 120 && req_y < 360) begin
            read_y = req_y - 10'd120;
            read_x = req_x - 10'd160;
            use_fb = 1'b1;
        end
    end
end

wire [16:0] rd_idx = (read_y << 8) + (read_y << 6) + read_x;
wire [16:0] clamped_rd_idx = (rd_idx > 17'd76799) ? 17'd76799 : rd_idx;

reg [4:0] use_rd_bank;
always @(posedge clk) begin
    use_rd_bank <= clamped_rd_idx[16:12]; 
end

// ==========================================
// 4. BRAM 写逻辑 
// ==========================================
reg [9:0] req_x_d1, req_y_d1;
reg       req_d1;
reg       use_fb_d1;

always @(posedge clk) begin
    req_d1    <= vga_rd_req;
    req_x_d1  <= req_x;
    req_y_d1  <= req_y;
    use_fb_d1 <= use_fb; 
end

reg [9:0] write_y, write_x;
reg       wr_en;

always @(*) begin
    wr_en   = 1'b0;
    write_y = 10'd0;
    write_x = 10'd0;
    
    if (req_d1) begin
        if (active_mode == MODE_ZOOM_IN) begin
            // 存入原图中心区域
            if (req_x_d1 >= 160 && req_x_d1 < 480 && req_y_d1 >= 120 && req_y_d1 < 360) begin
                write_y = req_y_d1 - 10'd120;
                write_x = req_x_d1 - 10'd160;
                wr_en   = 1'b1;
            end
        end else if (active_mode == MODE_ZOOM_OUT) begin
            // 隔行隔列下采样存入
            if (req_x_d1[0] == 0 && req_y_d1[0] == 0) begin
                write_y = req_y_d1 >> 1;
                write_x = req_x_d1 >> 1;
                wr_en   = 1'b1;
            end
        end
    end
end

wire [16:0] wr_idx = (write_y << 8) + (write_y << 6) + write_x;
wire [16:0] clamped_wr_idx = (wr_idx > 17'd76799) ? 17'd76799 : wr_idx;

wire [4:0]  wr_bank = clamped_wr_idx[16:12]; 
wire [11:0] wr_addr = clamped_wr_idx[11:0];  
wire [11:0] rd_addr = clamped_rd_idx[11:0];

// ==========================================
// 5. 19-Bank BRAM 阵列
// ==========================================
(* ram_style = "block" *) reg [15:0] bank00 [0:4095]; (* ram_style = "block" *) reg [15:0] bank01 [0:4095];
(* ram_style = "block" *) reg [15:0] bank02 [0:4095]; (* ram_style = "block" *) reg [15:0] bank03 [0:4095];
(* ram_style = "block" *) reg [15:0] bank04 [0:4095]; (* ram_style = "block" *) reg [15:0] bank05 [0:4095];
(* ram_style = "block" *) reg [15:0] bank06 [0:4095]; (* ram_style = "block" *) reg [15:0] bank07 [0:4095];
(* ram_style = "block" *) reg [15:0] bank08 [0:4095]; (* ram_style = "block" *) reg [15:0] bank09 [0:4095];
(* ram_style = "block" *) reg [15:0] bank10 [0:4095]; (* ram_style = "block" *) reg [15:0] bank11 [0:4095];
(* ram_style = "block" *) reg [15:0] bank12 [0:4095]; (* ram_style = "block" *) reg [15:0] bank13 [0:4095];
(* ram_style = "block" *) reg [15:0] bank14 [0:4095]; (* ram_style = "block" *) reg [15:0] bank15 [0:4095];
(* ram_style = "block" *) reg [15:0] bank16 [0:4095]; (* ram_style = "block" *) reg [15:0] bank17 [0:4095];
(* ram_style = "block" *) reg [15:0] bank18 [0:4095];

always @(posedge clk) begin
    if (wr_en) begin
        case (wr_bank)
            5'd00: bank00[wr_addr] <= din; 5'd01: bank01[wr_addr] <= din;
            5'd02: bank02[wr_addr] <= din; 5'd03: bank03[wr_addr] <= din;
            5'd04: bank04[wr_addr] <= din; 5'd05: bank05[wr_addr] <= din;
            5'd06: bank06[wr_addr] <= din; 5'd07: bank07[wr_addr] <= din;
            5'd08: bank08[wr_addr] <= din; 5'd09: bank09[wr_addr] <= din;
            5'd10: bank10[wr_addr] <= din; 5'd11: bank11[wr_addr] <= din;
            5'd12: bank12[wr_addr] <= din; 5'd13: bank13[wr_addr] <= din;
            5'd14: bank14[wr_addr] <= din; 5'd15: bank15[wr_addr] <= din;
            5'd16: bank16[wr_addr] <= din; 5'd17: bank17[wr_addr] <= din;
            5'd18: bank18[wr_addr] <= din;
            default: ;
        endcase
    end
end

reg [15:0] q00, q01, q02, q03, q04, q05, q06, q07, q08, q09;
reg [15:0] q10, q11, q12, q13, q14, q15, q16, q17, q18;

always @(posedge clk) begin
    q00 <= bank00[rd_addr]; q01 <= bank01[rd_addr];
    q02 <= bank02[rd_addr]; q03 <= bank03[rd_addr];
    q04 <= bank04[rd_addr]; q05 <= bank05[rd_addr];
    q06 <= bank06[rd_addr]; q07 <= bank07[rd_addr];
    q08 <= bank08[rd_addr]; q09 <= bank09[rd_addr];
    q10 <= bank10[rd_addr]; q11 <= bank11[rd_addr];
    q12 <= bank12[rd_addr]; q13 <= bank13[rd_addr];
    q14 <= bank14[rd_addr]; q15 <= bank15[rd_addr];
    q16 <= bank16[rd_addr]; q17 <= bank17[rd_addr];
    q18 <= bank18[rd_addr];
end

reg [15:0] rd_data;
always @(*) begin
    case (use_rd_bank)
        5'd00: rd_data = q00; 5'd01: rd_data = q01;
        5'd02: rd_data = q02; 5'd03: rd_data = q03;
        5'd04: rd_data = q04; 5'd05: rd_data = q05;
        5'd06: rd_data = q06; 5'd07: rd_data = q07;
        5'd08: rd_data = q08; 5'd09: rd_data = q09;
        5'd10: rd_data = q10; 5'd11: rd_data = q11;
        5'd12: rd_data = q12; 5'd13: rd_data = q13;
        5'd14: rd_data = q14; 5'd15: rd_data = q15;
        5'd16: rd_data = q16; 5'd17: rd_data = q17;
        5'd18: rd_data = q18;
        default: rd_data = 16'd0;
    endcase
end

// ==========================================
// 6. 最终输出
// ==========================================
always @(*) begin
    if (active_mode == MODE_ORIG) begin
        // 原图透传
        dout = din;     
    end else begin
        if (use_fb_d1) 
            dout = rd_data;
        else 
            dout = 16'h0000; // 非有效显示区强行赋纯黑
    end
end

endmodule