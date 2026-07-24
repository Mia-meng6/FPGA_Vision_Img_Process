`timescale 1ns / 1ps
module equalization(
    input                clk                ,
    input                rst_n              ,
    input       [7:0]    i_y                ,
    input                i_valid            ,
    input                i_hsync            ,
    input                i_vsync            ,
    output      [7:0]    o_y                ,
    output               o_valid            ,
    output               o_hsync            ,
    output               o_vsync            ,
    input       [19:0]   i_histogram        ,
    input                i_histogram_valid  
);

    // ========================================================
    // 1. CDF 累加与归一化计算 
    // ========================================================
    reg [19:0] cdf;
    reg [7:0]  map_addr;
    reg [7:0]  mapping_ram [255:0]; 
    // Y_out = (CDF * 255) / 307200 等效于 (CDF * 870) >> 20
    wire [29:0] mult_result = cdf * 10'd870;      
    wire [7:0]  mapped_val  = mult_result[27:20]; 
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cdf <= 20'd0;
            map_addr <= 8'd0;
        end else if (i_histogram_valid) begin
            cdf <= cdf + i_histogram;
            mapping_ram[map_addr] <= mapped_val; 
            map_addr <= map_addr + 1'b1;
        end else begin
            cdf <= 20'd0;      
            map_addr <= 8'd0;
        end
    end

    // ========================================================
    // 2. 延迟对齐
    // ========================================================
    reg [7:0]  y_out_reg;
    reg        valid_reg;
    reg        hsync_reg;
    reg        vsync_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_out_reg <= 8'd0; valid_reg <= 1'b0;
            hsync_reg <= 1'b0; vsync_reg <= 1'b0;
        end else begin
            y_out_reg <= mapping_ram[i_y]; // 查表
            valid_reg <= i_valid;
            hsync_reg <= i_hsync;
            vsync_reg <= i_vsync;
        end
    end
    
    assign o_y     = y_out_reg;
    assign o_valid = valid_reg;
    assign o_hsync = hsync_reg;
    assign o_vsync = vsync_reg;

endmodule