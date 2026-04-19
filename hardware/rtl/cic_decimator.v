// hardware/rtl/cic_decimator.v
// CIC Decimator: N integrators @ fs, downsample ÷R, N comb @ fs/R
// Input: signed B_in bits (from complex_mixer: 13-bit I or Q)
// Internal width: B_in + N*LOG2_RMAX bits (no multipliers)
// Output: 16-bit signed with rounding
// AXI-Lite: offset 0x00 = decimation_r[6:0] (valid: 15, 30, 60, 120)

module cic_decimator #(
    parameter N         = 5,
    parameter B_IN      = 13,
    parameter LOG2_RMAX = 7,                         // ceil(log2(120))=7
    parameter B_INT     = B_IN + N * LOG2_RMAX,      // 48
    parameter B_OUT     = 16,
    parameter AXI_ADDR_WIDTH = 4
)(
    input  wire                 clk,
    input  wire                 resetn,

    // Input @ fs (from complex_mixer)
    input  wire [B_IN-1:0]      din,
    input  wire                 din_valid,

    // Output @ fs/R
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

// --- AXI-Lite: decimation register ---
reg [6:0] decimation_r;  // valid: 15, 30, 60, 120

always @(posedge clk) begin
    if (!resetn) begin
        decimation_r   <= 7'd30;
        s_axil_awready <= 1'b0;
        s_axil_wready  <= 1'b0;
        s_axil_bvalid  <= 1'b0;
        s_axil_bresp   <= 2'b00;
    end else begin
        s_axil_awready <= s_axil_awvalid & s_axil_wvalid & ~s_axil_awready;
        s_axil_wready  <= s_axil_awvalid & s_axil_wvalid & ~s_axil_wready;
        if (s_axil_awvalid && s_axil_wvalid && s_axil_awready && s_axil_wready) begin
            decimation_r  <= s_axil_wdata[6:0];
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
            s_axil_rdata   <= {25'd0, decimation_r};
            s_axil_rresp   <= 2'b00;
            s_axil_rvalid  <= 1'b1;
        end else
            s_axil_arready <= 1'b0;
        if (s_axil_rvalid && s_axil_rready)
            s_axil_rvalid <= 1'b0;
    end
end

// --- Integrators @ fs ---
reg signed [B_INT-1:0] integ [0:N-1];

integer k;
always @(posedge clk) begin
    if (!resetn) begin
        for (k = 0; k < N; k = k + 1)
            integ[k] <= {B_INT{1'b0}};
    end else if (din_valid) begin
        integ[0] <= integ[0] + {{(B_INT-B_IN){din[B_IN-1]}}, din};
        for (k = 1; k < N; k = k + 1)
            integ[k] <= integ[k] + integ[k-1];
    end
end

// --- Downsampler ÷R ---
reg [6:0]             dec_cnt;
reg signed [B_INT-1:0] ds_reg;
reg                   ds_valid;

always @(posedge clk) begin
    if (!resetn) begin
        dec_cnt  <= 7'd0;
        ds_valid <= 1'b0;
    end else if (din_valid) begin
        if (dec_cnt == decimation_r - 1) begin
            dec_cnt  <= 7'd0;
            ds_reg   <= integ[N-1];
            ds_valid <= 1'b1;
        end else begin
            dec_cnt  <= dec_cnt + 1'b1;
            ds_valid <= 1'b0;
        end
    end else
        ds_valid <= 1'b0;
end

// --- Comb sections @ fs/R ---
reg signed [B_INT-1:0] comb_in  [0:N-1];
reg signed [B_INT-1:0] comb_dly [0:N-1];
reg signed [B_INT-1:0] comb_out [0:N-1];
reg                   comb_valid [0:N-1];

integer j;
always @(posedge clk) begin
    if (!resetn) begin
        for (j = 0; j < N; j = j + 1) begin
            comb_in[j]    <= {B_INT{1'b0}};
            comb_dly[j]   <= {B_INT{1'b0}};
            comb_out[j]   <= {B_INT{1'b0}};
            comb_valid[j] <= 1'b0;
        end
    end else begin
        // Stage 0: fed from downsampler
        if (ds_valid) begin
            comb_dly[0]   <= comb_in[0];
            comb_in[0]    <= ds_reg;
            comb_out[0]   <= ds_reg - comb_in[0];
            comb_valid[0] <= 1'b1;
        end else
            comb_valid[0] <= 1'b0;
        // Stages 1..N-1
        for (j = 1; j < N; j = j + 1) begin
            if (comb_valid[j-1]) begin
                comb_dly[j]   <= comb_in[j];
                comb_in[j]    <= comb_out[j-1];
                comb_out[j]   <= comb_out[j-1] - comb_in[j];
                comb_valid[j] <= 1'b1;
            end else
                comb_valid[j] <= 1'b0;
        end
    end
end

// --- Output rounding: truncate B_INT -> B_OUT ---
// Drop bottom (B_INT - B_OUT - 1) bits, round by adding 0.5 LSB
localparam SHIFT = B_INT - B_OUT;  // 32
wire signed [B_INT-1:0] cic_out   = comb_out[N-1];
wire signed [B_INT-1:0] rounded   = cic_out + {{(B_INT-1){1'b0}}, cic_out[SHIFT-1]};

always @(posedge clk) begin
    if (!resetn) begin
        dout       <= {B_OUT{1'b0}};
        dout_valid <= 1'b0;
    end else if (comb_valid[N-1]) begin
        dout       <= rounded[B_INT-1:SHIFT];
        dout_valid <= 1'b1;
    end else
        dout_valid <= 1'b0;
end

endmodule

