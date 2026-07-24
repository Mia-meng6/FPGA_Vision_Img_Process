`timescale 1ns/1ps
// =============================================================================
// Module  : line_buffer_3x3
// =============================================================================
module line_buffer_3x3 #(
    parameter IMG_WIDTH = 640
)(
    input  wire           clk,
    input  wire           rst_n,
    input  wire           iDataEnable,
    input  wire  [7:0]    din,
    
    output reg   [7:0]    p11,
    output reg   [7:0]    p12,
    output reg   [7:0]    p13,
    output reg   [7:0]    p21,
    output reg   [7:0]    p22,
    output reg   [7:0]    p23,
    output reg   [7:0]    p31,
    output reg   [7:0]    p32,
    output reg   [7:0]    p33
);

    reg [9:0] ptr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr <= 10'd0;
        end else if (iDataEnable) begin
            ptr <= (ptr == IMG_WIDTH - 1) ? 10'd0 : ptr + 1'b1;
        end else begin
            ptr <= 10'd0; 
        end
    end

    (* ram_style = "block" *) reg [7:0] ram1 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] ram2 [0:IMG_WIDTH-1];

    reg [9:0] ptr_d1;
    reg [7:0] din_d1;
    reg [7:0] q1_raw;
    reg [7:0] q2_raw;

    always @(posedge clk) begin
        if (iDataEnable) begin
            ptr_d1       <= ptr;
            din_d1       <= din;
            
            q1_raw       <= ram1[ptr];
            ram1[ptr_d1] <= din_d1;
            
            q2_raw       <= ram2[ptr];
            ram2[ptr_d1] <= q1_raw;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p11 <= 8'd0;
            p12 <= 8'd0;
            p13 <= 8'd0;
            p21 <= 8'd0;
            p22 <= 8'd0;
            p23 <= 8'd0;
            p31 <= 8'd0;
            p32 <= 8'd0;
            p33 <= 8'd0;
        end else if (iDataEnable) begin
            p33 <= din_d1;
            p23 <= q1_raw;
            p13 <= q2_raw;
            
            p32 <= p33;
            p22 <= p23;
            p12 <= p13;
            
            p31 <= p32;
            p21 <= p22;
            p11 <= p12;
        end
    end

endmodule