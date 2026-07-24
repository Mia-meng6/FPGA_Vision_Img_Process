`timescale 1ns/1ns
module Line_Shift_RAM_16Bit #(
    parameter RAM_DEPTH = 640  
) (
    input  wire         clock,
    input  wire         clken,     
    input  wire [15:0]  shiftin,   
    output wire [15:0]  shiftout   
);
    reg [15:0] ram [0:RAM_DEPTH-1];
    reg [10:0] addr; 
    reg [15:0] shiftout_reg;

    initial begin
        addr = 11'd0;
        shiftout_reg = 16'd0;
    end

    always @(posedge clock) begin
        if (clken) begin
            shiftout_reg <= ram[addr];
            ram[addr] <= shiftin;
            if (addr == RAM_DEPTH - 1) addr <= 11'd0;
            else addr <= addr + 11'd1;
        end
    end
    assign shiftout = shiftout_reg;
endmodule