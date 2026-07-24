`timescale 1ns / 1ps
module histogram_adjust(
    input         clk     ,
    input         rst_n   ,
    input [7:0]   i_y     ,
    input         i_valid ,
    input         i_hsync ,
    input         i_vsync ,
    output [19:0] o_histogram,
    output reg    o_histogram_valid
);
    reg [19:0] ram [255:0];
    reg [19:0] ram_q;
    reg [1:0]  vsync_reg;
    reg [7:0]  out_addr;
    reg        valid_internal;
    reg [7:0]  clear_addr;
    reg        is_clearing;

    wire [7:0] ram_rd_addr = valid_internal ? out_addr : i_y;
    
    always @(posedge clk) begin
        ram_q <= ram[ram_rd_addr];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            is_clearing <= 1'b0; 
            clear_addr  <= 8'd0;
        end else if (~vsync_reg[0] && vsync_reg[1]) begin 
            is_clearing <= 1'b1; 
            clear_addr  <= 8'd0;
        end else if (is_clearing) begin
            if (clear_addr == 8'd255) 
                is_clearing <= 1'b0;
            else 
                clear_addr <= clear_addr + 1'b1;
        end
    end

    always @(posedge clk) begin
        vsync_reg <= {vsync_reg[0], i_vsync};
    end
    
    reg [7:0]  y_r1, y_r2;
    reg        valid_r1, valid_r2;
    reg [19:0] count_r1, count_r2;
    
    always @(posedge clk) begin
        y_r1 <= i_y;
        valid_r1 <= i_valid;
        count_r1 <= ram_q;  
        y_r2 <= y_r1;
        valid_r2 <= valid_r1;
        count_r2 <= count_r1 + 20'd1;
    end
    always @(posedge clk) begin
        if (is_clearing) begin
            ram[clear_addr] <= 20'd0;
        end else if (valid_r2) begin
            ram[y_r2] <= count_r2;
        end
    end
    always @(posedge clk) begin
        if(!rst_n || out_addr == 8'd255) 
            valid_internal <= 1'b0;
        else if(vsync_reg[0] && ~vsync_reg[1]) 
            valid_internal <= 1'b1;
    end
    always @(posedge clk) begin
        if(!rst_n) 
            out_addr <= 8'd0;
        else if(valid_internal) 
            out_addr <= out_addr + 1'b1;
    end
    always @(posedge clk) begin
        if(!rst_n) 
            o_histogram_valid <= 1'b0;
        else 
            o_histogram_valid <= valid_internal;
    end
    assign o_histogram = ram_q;
endmodule