module img_proc #(
    parameter IMG_WIDTH  = 640,
    parameter GUIDED_DLY = 38
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        iHSync,
    input  wire        iVSync,
    input  wire        iDataEnable,  
    input  wire [15:0] iRGB565,
    input  wire [1:0]  mode_sel,     

    output reg         oHSync,
    output reg         oVSync,
    output reg         oDataEnable,
    output reg  [15:0] oRGB565
);

    reg [43:0] de_sr, hs_sr, vs_sr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_sr <= 44'd0;
            hs_sr <= 44'd0;
            vs_sr <= 44'd0;
        end else begin
            de_sr <= {de_sr[42:0], iDataEnable};
            hs_sr <= {hs_sr[42:0], iHSync};
            vs_sr <= {vs_sr[42:0], iVSync};
        end
    end
    wire de_44d = de_sr[43];
    wire hs_44d = hs_sr[43];
    wire vs_44d = vs_sr[43];

    wire [7:0] R8 = {iRGB565[15:11], iRGB565[15:13]};
    wire [7:0] G8 = {iRGB565[10:5],  iRGB565[10:9]};
    wire [7:0] B8 = {iRGB565[4:0],   iRGB565[4:2]};
    wire [7:0] y_in, cb_in, cr_in;
    wire       ycbcr_hs, ycbcr_vs, ycbcr_de;
    rgb_to_ycbcr u_rgb2ycbcr (
        .clk       (clk),
        .i_r_8b    (R8),
        .i_g_8b    (G8),
        .i_b_8b    (B8),
        .i_h_sync  (iHSync),
        .i_v_sync  (iVSync),
        .i_data_en (iDataEnable),
        .o_y_8b    (y_in),
        .o_cb_8b   (cb_in),
        .o_cr_8b   (cr_in),
        .o_h_sync  (ycbcr_hs),
        .o_v_sync  (ycbcr_vs),
        .o_data_en (ycbcr_de)
    );
    wire [7:0] y_filt;
    wire       gf_hs, gf_vs, gf_de;
    guided_filter #(
        .IMG_WIDTH (IMG_WIDTH),
        .EPS_Q8    (16'd2500)
    ) u_gf (
        .clk         (clk),
        .rst_n       (rst_n),
        .iHSync      (ycbcr_hs),
        .iVSync      (ycbcr_vs),
        .iDataEnable (ycbcr_de),
        .iData       (y_in),
        .oHSync      (gf_hs),
        .oVSync      (gf_vs),
        .oDataEnable (gf_de),
        .oData       (y_filt)
    );

    reg [7:0] cb_dly [0:40];
    reg [7:0] cr_dly [0:40];
    genvar i;
    generate
        for (i=0; i<=40; i=i+1) begin : delay_cbcr
            if (i==0) begin
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        cb_dly[0] <= 8'd0;
                        cr_dly[0] <= 8'd0;
                    end else begin
                        cb_dly[0] <= cb_in;
                        cr_dly[0] <= cr_in;
                    end
                end
            end else begin
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        cb_dly[i] <= 8'd0;
                        cr_dly[i] <= 8'd0;
                    end else begin
                        cb_dly[i] <= cb_dly[i-1];
                        cr_dly[i] <= cr_dly[i-1];
                    end
                end
            end
        end
    endgenerate
    wire [7:0] cb_aligned = cb_dly[40];
    wire [7:0] cr_aligned = cr_dly[40];

    wire [7:0] r_proc, g_proc, b_proc;
    ycbcr_to_rgb u_ycbcr2rgb (
        .clk       (clk),
        .i_y_8b    (y_filt),
        .i_cb_8b   (cb_aligned),
        .i_cr_8b   (cr_aligned),
        .i_h_sync  (gf_hs),
        .i_v_sync  (gf_vs),
        .i_data_en (gf_de),
        .o_r_8b    (r_proc),
        .o_g_8b    (g_proc),
        .o_b_8b    (b_proc),
        .o_h_sync  (),
        .o_v_sync  (),
        .o_data_en ()
    );
    wire [15:0] proc_rgb565 = {r_proc[7:3], g_proc[7:2], b_proc[7:3]};

    wire skin_raw;
    skin_detection u_skin (
        .clk       (clk),
        .rst_n     (rst_n),
        .pixel     (iRGB565),
        .skin_flag (skin_raw)        
    );

    reg de_1d;
    always @(posedge clk) begin
        de_1d <= iDataEnable;
    end

    wire mask_dilated;
    skin_dilate_3x3 #(.IMG_WIDTH(IMG_WIDTH)) u_dilate (
        .clk        (clk),
        .rst_n      (rst_n),
        .iDataEnable(de_1d),
        .din        (skin_raw),
        .dout       (mask_dilated)
    );

    wire de_3d = de_sr[2];
    reg mask_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mask_valid <= 1'b0;
        else if (de_3d)
            mask_valid <= mask_dilated;
        else
            mask_valid <= 1'b0;
    end

    reg [40:0] mask_shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mask_shift <= 41'd0;
        else
            mask_shift <= {mask_shift[39:0], mask_valid};
    end
    wire skin_aligned = mask_shift[40];   

    reg [15:0] straight_rgb [0:43];
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j=0; j<=43; j=j+1)
                straight_rgb[j] <= 16'd0;
        end else begin
            straight_rgb[0] <= iRGB565;
            for (j=1; j<=43; j=j+1)
                straight_rgb[j] <= straight_rgb[j-1];
        end
    end
    wire [15:0] rgb_delayed = straight_rgb[43];

    wire [15:0] out_pixel = (mode_sel == 2'd1) ? (skin_aligned ? proc_rgb565 : rgb_delayed)
                                                : rgb_delayed;

    reg [15:0] out_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_reg <= 16'd0;
            oDataEnable <= 1'b0;
            oHSync      <= 1'b0;
            oVSync      <= 1'b0;
        end else begin
            out_reg     <= out_pixel;
            oHSync      <= hs_44d;
            oVSync      <= vs_44d;
            oDataEnable <= de_44d;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            oRGB565 <= 16'd0;
        else
            oRGB565 <= de_44d ? out_reg : 16'd0;
    end

endmodule