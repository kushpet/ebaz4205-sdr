// hardware/rtl/cic_interpolator.v
// CIC Interpolator: N comb @ fs/R, upsample ×R (zero-insert), N integrators @ fs
// Mirror structure of cic_decimator for DUC path
// Input: 16-bit signed @ fs/R (from hb_fir_interpolator)
// Output: B_INT-bit signed @ fs, truncated to B_OUT=16 with rounding
// AXI-Lite: offset 0x00 = interpolation_r[6:0] (valid: 15, 30, 60, 120)

module cic_interpolator #(
    parameter N         = 5,
    parameter B_IN      = 16,
    parameter LOG2_RMAX = 7,
    parameter B_INT     = B_IN + N * LOG2_RMAX,  // 51
    parameter B_OUT     = 16,
    parameter AXI_ADDR_WIDTH = 4
)(
    input  wire                 clk,
    input  wire                 resetn,

    // Input @ fs/R
    input  wire [B_IN-1:0]      din,
    input  wire                 din_valid,

    // Output @ fs
    output reg  [B_OUT-1:0]     dout,
    output reg                  dout_valid,

    // AXI-Lite slave
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_awaddr,
    input  wire                 s_axil_awvalid,
    output reg                  s_axil_awready,
    input  wire [31:0]          s_axil_wdata,
    input  wire                 s_axil_wvalid,
    output reg                  s_axil_wready,
    output reg  [1:0]           s_axil_bresp,
    output reg                  s_axil_bvalid,
    input  wire                 s_axil_bready,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_araddr,
    input  wire                 s_axil_arvalid,
    output reg                  s_axil_arready,
    output reg  [31:0]          s_axil_rdata,
    output reg  [1:0]           s_axil_rresp,
    output reg                  s_axil_rvalid,
    input  wire                 s_axil_rready
);

// --- AXI-Lite ---
reg [6:0] interp_r;

always @(posedge clk) begin
    if (!resetn) begin
        interp_r       <= 7'd30;
        s_axil_awready <= 1'b0;
        s_axil_wready  <= 1'b0;
        s_axil_bvalid  <= 1'b0;
        s_axil_bresp   <= 2'b00;
    end else begin
        s_axil_awready <= s_axil_awvalid & s_axil_wvalid & ~s_axil_awready;
        s_axil_wready  <= s_axil_awvalid & s_axil_wvalid & ~s_axil_wready;
        if (s_axil_awvalid && s_axil_wvalid && s_axil_awready && s_axil_wready) begin
            interp_r      <= s_axil_wdata[6:0];
            s_axil_bvalid <= 1'b1;
            s_axil_bresp  <= 2'b00;
        end else if (s_axil_bready)
            s_axil_bvalid <= 1'b0;
    end
end

always @(posedge clk) begin
    if (!resetn) begin
        s_axil_arready <= 1'b0;
        s_axil_rvalid  <= 1'b0;
        s_axil_rdata   <= 32'd0;
        s_axil_rresp   <= 2'b00;
    end else begin
        if (s_axil_arvalid && ~s_axil_arready) begin
            s_axil_arready <= 1'b1;
            s_axil_rdata   <= {25'd0, interp_r};
            s_axil_rresp   <= 2'b00;
            s_axil_rvalid  <= 1'b1;
        end else
            s_axil_arready <= 1'b0;
        if (s_axil_rvalid && s_axil_rready)
            s_axil_rvalid <= 1'b0;
    end
end

// --- Comb sections @ fs/R ---
reg signed [B_INT-1:0] comb_in  [0:N-1];
reg signed [B_INT-1:0] comb_out [0:N-1];
reg                   comb_valid [0:N-1];

integer j;
always @(posedge clk) begin
    if (!resetn) begin
        for (j = 0; j < N; j = j + 1) begin
            comb_in[j]    <= {B_INT{1'b0}};
            comb_out[j]   <= {B_INT{1'b0}};
            comb_valid[j] <= 1'b0;
        end
    end else begin
        if (din_valid) begin
            comb_out[0]   <= {{(B_INT-B_IN){din[B_IN-1]}}, din} - comb_in[0];
            comb_in[0]    <= {{(B_INT-B_IN){din[B_IN-1]}}, din};
            comb_valid[0] <= 1'b1;
        end else
            comb_valid[0] <= 1'b0;
        for (j = 1; j < N; j = j + 1) begin
            if (comb_valid[j-1]) begin
                comb_out[j]   <= comb_out[j-1] - comb_in[j];
                comb_in[j]    <= comb_out[j-1];
                comb_valid[j] <= 1'b1;
            end else
                comb_valid[j] <= 1'b0;
        end
    end
end

// --- Upsampler ×R (zero insertion) ---
reg [6:0]              up_cnt;
reg signed [B_INT-1:0] up_sample;
reg                    up_pulse;  // one cycle @ fs when new comb output arrives

always @(posedge clk) begin
    if (!resetn) begin
        up_cnt    <= 7'd0;
        up_pulse  <= 1'b0;
        up_sample <= {B_INT{1'b0}};
    end else begin
        up_pulse <= 1'b0;
        if (comb_valid[N-1]) begin
            up_sample <= comb_out[N-1];
            up_cnt    <= 7'd0;
            up_pulse  <= 1'b1;
        end else if (up_cnt < interp_r - 1) begin
            up_cnt   <= up_cnt + 1'b1;
            up_pulse <= 1'b1;  // zero-insert: pass zero each clock @ fs
        end
    end
end

wire signed [B_INT-1:0] up_data = (up_cnt == 7'd0 && up_pulse) ? up_sample : {B_INT{1'b0}};

// --- Integrators @ fs ---
reg signed [B_INT-1:0] integ [0:N-1];

integer k;
always @(posedge clk) begin
    if (!resetn) begin
        for (k = 0; k < N; k = k + 1)
            integ[k] <= {B_INT{1'b0}};
    end else if (up_pulse) begin
        integ[0] <= integ[0] + up_data;
        for (k = 1; k < N; k = k + 1)
            integ[k] <= integ[k] + integ[k-1];
    end
end

// --- Output rounding: B_INT -> B_OUT ---
localparam SHIFT = B_INT - B_OUT;  // 35
wire signed [B_INT-1:0] cic_out = integ[N-1];
wire signed [B_INT-1:0] rounded = cic_out + {{(B_INT-1){1'b0}}, cic_out[SHIFT-1]};

always @(posedge clk) begin
    if (!resetn) begin
        dout       <= {B_OUT{1'b0}};
        dout_valid <= 1'b0;
    end else begin
        dout       <= rounded[B_INT-1:SHIFT];
        dout_valid <= up_pulse;
    end
end

endmodule

