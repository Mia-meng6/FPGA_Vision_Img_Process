`timescale 1ns/1ns
// =============================================================================
// 模块名：algo_mux
// 功  能：根据 algo_sel 切换算法处理效果，输出最终像素给 vga_ctrl
// =============================================================================
module algo_mux (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        vga_rd_req,
    input  wire [15:0] din,
    input  wire [5:0]  algo_sel,   // [5:4]=旋转角度 [3:0]=算法编号
    output reg  [15:0] dout
);

// ============================================================
// 1. 场同步下降沿 + 帧边界锁存 algo_sel（防撕裂）
// ============================================================
reg vsync_d1, vsync_d2;
always @(posedge clk) begin
    vsync_d1 <= vsync;
    vsync_d2 <= vsync_d1;
end
wire vsync_fall = vsync_d2 & ~vsync_d1;

reg [5:0] active_sel;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) active_sel <= 6'd0;
    else if (vsync_fall) active_sel <= algo_sel;
end
wire [3:0] active_algo = active_sel[3:0];   // 算法编号（低4位）

// ============================================================
// 2. 最终输出（统一寄存一拍，与 vga_ctrl 时序对齐）
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dout <= 16'd0;
    end else begin
        dout <= din;   
    end
end

endmodule