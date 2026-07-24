`timescale 1ns/1ps
// =============================================================================
// Module  : pipe_div_8
// =============================================================================
module pipe_div_8 (
    input   wire            clk,
    input   wire    [23:0]  num,
    input   wire    [15:0]  den,
    output  reg     [7:0]   quo
);

    // -------------------------------------------------------------------------
    reg     [23:0]  r7; 
    reg     [15:0]  d7; 
    reg             q7;
    always @(posedge clk) begin
        d7 <= den;
        if (num >= {den, 7'd0}) begin r7 <= num - {den, 7'd0}; q7 <= 1'b1; end
        else                    begin r7 <= num;               q7 <= 1'b0; end
    end

    // -------------------------------------------------------------------------
    reg     [23:0]  r6; 
    reg     [15:0]  d6; 
    reg     [1:0]   q6;
    always @(posedge clk) begin
        d6 <= d7;
        if (r7 >= {d7, 6'd0}) begin r6 <= r7 - {d7, 6'd0}; q6 <= {q7, 1'b1}; end
        else                  begin r6 <= r7;              q6 <= {q7, 1'b0}; end
    end

    // -------------------------------------------------------------------------
    reg     [23:0]  r5; 
    reg     [15:0]  d5; 
    reg     [2:0]   q5;
    always @(posedge clk) begin
        d5 <= d6;
        if (r6 >= {d6, 5'd0}) begin r5 <= r6 - {d6, 5'd0}; q5 <= {q6, 1'b1}; end
        else                  begin r5 <= r6;              q5 <= {q6, 1'b0}; end
    end

    // -------------------------------------------------------------------------
    reg     [23:0]  r4; 
    reg     [15:0]  d4; 
    reg     [3:0]   q4;
    always @(posedge clk) begin
        d4 <= d5;
        if (r5 >= {d5, 4'd0}) begin r4 <= r5 - {d5, 4'd0}; q4 <= {q5, 1'b1}; end
        else                  begin r4 <= r5;              q4 <= {q5, 1'b0}; end
    end

    // -------------------------------------------------------------------------
    reg     [23:0]  r3; 
    reg     [15:0]  d3; 
    reg     [4:0]   q3;
    always @(posedge clk) begin
        d3 <= d4;
        if (r4 >= {d4, 3'd0}) begin r3 <= r4 - {d4, 3'd0}; q3 <= {q4, 1'b1}; end
        else                  begin r3 <= r4;              q3 <= {q4, 1'b0}; end
    end

    // -------------------------------------------------------------------------
    reg     [23:0]  r2; 
    reg     [15:0]  d2; 
    reg     [5:0]   q2;
    always @(posedge clk) begin
        d2 <= d3;
        if (r3 >= {d3, 2'd0}) begin r2 <= r3 - {d3, 2'd0}; q2 <= {q3, 1'b1}; end
        else                  begin r2 <= r3;              q2 <= {q3, 1'b0}; end
    end

    // -------------------------------------------------------------------------
    reg     [23:0]  r1; 
    reg     [15:0]  d1; 
    reg     [6:0]   q1;
    always @(posedge clk) begin
        d1 <= d2;
        if (r2 >= {d2, 1'd0}) begin r1 <= r2 - {d2, 1'd0}; q1 <= {q2, 1'b1}; end
        else                  begin r1 <= r2;              q1 <= {q2, 1'b0}; end
    end

    //输出
    always @(posedge clk) begin
        if (den == 16'd0)     quo <= 8'd0; 
        else if (r1 >= d1)    quo <= {q1, 1'b1};
        else                  quo <= {q1, 1'b0};
    end

endmodule