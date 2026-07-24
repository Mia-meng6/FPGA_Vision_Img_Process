module skin_detection (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] pixel,
    output reg         skin_flag
);

// RGB565 转 8-bit RGB 
wire [7:0] R8;
wire [7:0] G8;
wire [7:0] B8;

assign R8 = {pixel[15:11], pixel[15:13]};
assign G8 = {pixel[10:5],  pixel[10:9]};
assign B8 = {pixel[4:0],   pixel[4:2]};

// RGB -> YCbCr 
wire [15:0] Y;
wire [15:0] Cb;
wire [15:0] Cr;

assign Y  = (77*R8 + 150*G8 + 29*B8) / 256;
assign Cb = (-43*R8 - 85*G8 + 128*B8) / 256 + 128;
assign Cr = (128*R8 - 107*G8 - 21*B8) / 256 + 128;

// 肤色范围 
wire skin;
assign skin = (Y > 16) && (Y < 235) &&
              (Cb > 77) && (Cb < 127) &&
              (Cr > 133) && (Cr < 173);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        skin_flag <= 1'b0;
    end else begin
        skin_flag <= skin;
    end
end

endmodule