`timescale 1ns/1ns
// =============================================================================
// Module  : RGB_Delay_Align
// Purpose : 将 smooth_base_rgb 延迟，与算法流水线末端对齐。
// =============================================================================
module RGB_Delay_Align #(
    parameter IMG_HDISP = 640
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         cmos_clken,      // 来自 smooth_base_clken
    input  wire [15:0]  cmos_rgb_data,   // 来自 smooth_base_rgb

    input  wire         sync_clken,      // 保留接口，不使用
    output wire [15:0]  aligned_rgb_data
);

    // ─── 6 级行延迟（clken 门控，跳过消隐期）────────────────────────────────
    wire [15:0] row1_out;
    Line_Shift_RAM_16Bit #(.RAM_DEPTH(IMG_HDISP)) u_Line_Delay_1 (
        .clock(clk), .clken(cmos_clken), .shiftin(cmos_rgb_data), .shiftout(row1_out));

    wire [15:0] row2_out;
    Line_Shift_RAM_16Bit #(.RAM_DEPTH(IMG_HDISP)) u_Line_Delay_2 (
        .clock(clk), .clken(cmos_clken), .shiftin(row1_out), .shiftout(row2_out));

    wire [15:0] row3_out;
    Line_Shift_RAM_16Bit #(.RAM_DEPTH(IMG_HDISP)) u_Line_Delay_3 (
        .clock(clk), .clken(cmos_clken), .shiftin(row2_out), .shiftout(row3_out));

    wire [15:0] row4_out;
    Line_Shift_RAM_16Bit #(.RAM_DEPTH(IMG_HDISP)) u_Line_Delay_4 (
        .clock(clk), .clken(cmos_clken), .shiftin(row3_out), .shiftout(row4_out));

    wire [15:0] row5_out;
    Line_Shift_RAM_16Bit #(.RAM_DEPTH(IMG_HDISP)) u_Line_Delay_5 (
        .clock(clk), .clken(cmos_clken), .shiftin(row4_out), .shiftout(row5_out));

    wire [15:0] row6_out;
    Line_Shift_RAM_16Bit #(.RAM_DEPTH(IMG_HDISP)) u_Line_Delay_6 (
        .clock(clk), .clken(cmos_clken), .shiftin(row5_out), .shiftout(row6_out));

    // 使用 clken 门控：消隐期内暂停，与算法管线的门控级同步
    reg [15:0] shift_regs [0:5];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 6; i = i + 1)
                shift_regs[i] <= 16'd0;
        end else if (cmos_clken) begin
            shift_regs[0] <= row6_out;
            for (i = 1; i < 6; i = i + 1)
                shift_regs[i] <= shift_regs[i-1];
        end
    end

    assign aligned_rgb_data = shift_regs[5];

endmodule