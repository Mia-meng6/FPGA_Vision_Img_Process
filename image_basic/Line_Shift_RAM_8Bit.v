`timescale 1ns/1ns
module Line_Shift_RAM_8Bit #(
    parameter RAM_DEPTH = 640  // 默认图像宽度为 640
) (
    input  wire         clock,
    input  wire         clken,     // 像素有效使能
    input  wire [7:0]   shiftin,   // 当前行输入的像素
    output wire [7:0]   shiftout   // 延迟一整行后输出的像素
);

    reg [7:0] ram [0:RAM_DEPTH-1];
    reg [10:0] addr; 
    reg [7:0] shiftout_reg;

    // ==========================================
    // 给地址指针和输出寄存器一个明确的起点
    // ==========================================
    initial begin
        addr = 11'd0;
        shiftout_reg = 8'd0;
    end

    always @(posedge clock) begin
        if (clken) begin
            // 先读出旧数据，再写入新数据
            shiftout_reg <= ram[addr];
            ram[addr] <= shiftin;
            
            // 地址指针循环递增
            if (addr == RAM_DEPTH - 1)
                addr <= 11'd0;
            else
                addr <= addr + 11'd1;
        end
    end

    assign shiftout = shiftout_reg;

endmodule