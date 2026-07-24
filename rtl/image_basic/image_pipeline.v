module image_pipeline (
    input  wire        clk,          // 25MHz
    input  wire        rst_n,
    input  wire        din_valid,    
    input  wire        vs_in,       
    input  wire [15:0] din,          
    input  wire        filter_en,   

    output wire        dout_valid,   
    output wire        vs_out,       
    output wire [15:0] dout         
);


wire        filtered1_valid;
wire [15:0] filtered1_data;
wire        filtered1_vs;

rgb_mean_filter_5x5 u_filter1 (
    .clk        (clk),
    .rst_n      (rst_n),
    .din_valid  (din_valid),
    .vs_in      (vs_in),
    .din        (din),
    .filter_en  (filter_en),
    .dout_valid (filtered1_valid),
    .vs_out     (filtered1_vs),
    .dout       (filtered1_data)
);

wire        filtered2_valid;
wire [15:0] filtered2_data;
wire        filtered2_vs;

rgb_mean_filter_5x5 u_filter2 (
    .clk        (clk),
    .rst_n      (rst_n),
    .din_valid  (filtered1_valid),
    .vs_in      (filtered1_vs),
    .din        (filtered1_data),
    .filter_en  (filter_en),
    .dout_valid (filtered2_valid),
    .vs_out     (filtered2_vs),
    .dout       (filtered2_data)
);

wire skin_flag_raw;
wire skin_flag_dilate;

skin_detection u_skin_detection (
    .clk      (clk),
    .rst_n    (rst_n),
    .pixel    (din),
    .skin_flag(skin_flag_raw)
);

skin_dilate u_skin_dilate (
    .clk       (clk),
    .rst_n     (rst_n),
    .mask_in   (skin_flag_raw),
    .din_valid (din_valid),
    .mask_out  (skin_flag_dilate)
);

reg [6:0] skin_shift;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        skin_shift <= 7'b0;
    else begin
        skin_shift[0] <= skin_flag_dilate;
        skin_shift[6:1] <= skin_shift[5:0];
    end
end
wire skin_flag_delayed = skin_shift[6];
wire pupil_flag_raw;
wire pupil_flag_dilate;

pupil_detection u_pupil_detection (
    .clk        (clk),
    .rst_n      (rst_n),
    .pixel      (din),
    .pupil_flag (pupil_flag_raw)
);

skin_dilate u_pupil_dilate (
    .clk       (clk),
    .rst_n     (rst_n),
    .mask_in   (pupil_flag_raw),
    .din_valid (din_valid),
    .mask_out  (pupil_flag_dilate)
);

reg [6:0] pupil_shift;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pupil_shift <= 7'b0;
    else begin
        pupil_shift[0] <= pupil_flag_dilate;
        pupil_shift[6:1] <= pupil_shift[5:0];
    end
end
wire pupil_flag_delayed = pupil_shift[6];

reg [15:0] raw_pipe [0:9];
integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 10; i = i + 1)
            raw_pipe[i] <= 16'd0;
    end else begin
        raw_pipe[0] <= din;
        for (i = 1; i < 10; i = i + 1)
            raw_pipe[i] <= raw_pipe[i-1];
    end
end
wire [15:0] raw_delayed = raw_pipe[9];

wire final_flag = skin_flag_delayed | pupil_flag_delayed;
wire [15:0] final_pixel = final_flag ? raw_delayed : filtered2_data;

assign dout_valid = filtered2_valid;
assign vs_out     = filtered2_vs;
assign dout       = final_pixel;

endmodule