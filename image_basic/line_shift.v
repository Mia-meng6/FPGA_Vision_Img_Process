module Line_Shift #(
    parameter TAP_DISTANCE = 640
) (
    input  wire       clock,
    input  wire       shiftin,
    output wire       shiftout,
    input  wire       clken,
    output wire [1:0] taps
);

reg ram1 [0:TAP_DISTANCE-1];
reg ram2 [0:TAP_DISTANCE-1];
reg [10:0] ptr = 11'd0;

// 上电初始化
integer i;
initial begin
    for(i=0; i<TAP_DISTANCE; i=i+1) begin
        ram1[i] = 1'b0;
        ram2[i] = 1'b0;
    end
end

always @(posedge clock) begin
    if (clken) begin
        ram1[ptr] <= shiftin;       
        ram2[ptr] <= ram1[ptr];    
        ptr <= (ptr == TAP_DISTANCE-1) ? 11'd0 : ptr + 11'd1;
    end
end

// taps[1] 是延时两行的数据 (row1_data)
// taps[0] 是延时一行的数据 (row2_data)
assign taps = {ram2[ptr], ram1[ptr]};
assign shiftout = ram2[ptr];

endmodule