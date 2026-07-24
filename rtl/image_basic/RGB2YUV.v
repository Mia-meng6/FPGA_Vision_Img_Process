`timescale 1ns / 1ps
module RGB2YUV(
    input         clk     ,
    input         rst_n   ,
    input [23:0]  i_rgb   ,
    input         i_valid ,
    input         i_hsync ,
    input         i_vsync ,
    output [7:0]  o_y     ,
    output        o_valid ,
    output        o_hsync ,
    output        o_vsync 
    );
    
    parameter C0 = 76 ,
               C1 = 150,
               C2 = 29 ;
    
    reg [15:0] temp0_r;
    reg [15:0] temp0_g;
    reg [15:0] temp0_b;
    reg [15:0] temp1_y;
    
    reg [1:0] valid_reg;   
    reg [1:0] hsync_reg;  
    reg [1:0] vsync_reg;  
    
    always @(posedge clk) begin
        if(!rst_n) begin
            temp0_r <= 0;
            temp0_g <= 0;
            temp0_b <= 0;
        end
        else begin
            temp0_r <= i_rgb[23:16] * C0;
            temp0_g <= i_rgb[15:8]  * C1;
            temp0_b <= i_rgb[7:0]   * C2;
        end
    end
    
    always @(posedge clk) begin
        if(!rst_n)
            temp1_y <= 0;
        else 
            temp1_y <= temp0_r + temp0_g + temp0_b;
    end
    
    always @(posedge clk) begin
        valid_reg <= {valid_reg[0], i_valid};
        hsync_reg <= {hsync_reg[0], i_hsync};
        vsync_reg <= {vsync_reg[0], i_vsync};
    end 
    
    assign o_y     = temp1_y[15:8];
    assign o_valid = valid_reg[1];
    assign o_hsync = hsync_reg[1];
    assign o_vsync = vsync_reg[1];
    
endmodule