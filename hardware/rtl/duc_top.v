// hardware/rtl/duc_top.v
// DUC top: AXI-Stream I/Q -> hb_fir_interpolator -> cic_interpolator -> complex_mixer -> dac_if
// NCO shared with DDC (nco_direct, same freq_word register bank)
// AXI-Lite register map:
//   0x00: nco_freq_word[31:0]
//   0x04: interpolation_rate[6:0]  (15/30/60/120)
//   0x08: dac_ctrl[31:0]           (bit0 = DAC PD)

`timescale 1ns/1ps

module duc_top #(
    parameter AXI_ADDR_WIDTH = 4
)(
    input  wire        clk,         // 60 MHz
    input  wire        resetn,

    // AXI-Stream I/Q slave (from PS DMA)
    // tdata[31:16]=Q, tdata[15:0]=I (16-bit signed)
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    // AXI-Lite slave (single control block)
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,
    input  wire [31:0] s_axil_wdata,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,
    output wire [1:0]  s_axil_bresp,
    output wire        s_axil_bvalid,
    input  wire        s_axil_bready,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_araddr,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,
    output wire [31:0] s_axil_rdata,
    output wire [1:0]  s_axil_rresp,
    output wire        s_axil_rvalid,
    input  wire        s_axil_rready,

    // DAC904 physical pins
    output wire [13:0] DAC,
    output wire        CLK_DAC,
    output wire        PD
);

// ============================================================
// AXI-Lite: register bank
// ============================================================
reg [31:0] reg_nco_freq;   // 0x00
reg [6:0]  reg_interp_rate; // 0x04 [6:0]
reg [31:0] reg_dac_ctrl;   // 0x08

reg        axil_awready_r, axil_wready_r, axil_bvalid_r;
reg [1:0]  axil_bresp_r;
reg        axil_arready_r, axil_rvalid_r;
reg [31:0] axil_rdata_r;
reg [1:0]  axil_rresp_r;

assign s_axil_awready = axil_awready_r;
assign s_axil_wready  = axil_wready_r;
assign s_axil_bresp   = axil_bresp_r;
assign s_axil_bvalid  = axil_bvalid_r;
assign s_axil_arready = axil_arready_r;
assign s_axil_rdata   = axil_rdata_r;
assign s_axil_rresp   = axil_rresp_r;
assign s_axil_rvalid  = axil_rvalid_r;

always @(posedge clk) begin
    if (!resetn) begin
        reg_nco_freq    <= 32'd0;
        reg_interp_rate <= 7'd30;
        reg_dac_ctrl    <= 32'd0;
        axil_awready_r  <= 1'b0;
        axil_wready_r   <= 1'b0;
        axil_bvalid_r   <= 1'b0;
        axil_bresp_r    <= 2'b00;
    end else begin
        axil_awready_r <= s_axil_awvalid & s_axil_wvalid & ~axil_awready_r;
        axil_wready_r  <= s_axil_awvalid & s_axil_wvalid & ~axil_wready_r;
        if (s_axil_awvalid && s_axil_wvalid && axil_awready_r && axil_wready_r) begin
            case (s_axil_awaddr[3:2])
                2'b00: reg_nco_freq    <= s_axil_wdata;
                2'b01: reg_interp_rate <= s_axil_wdata[6:0];
                2'b10: reg_dac_ctrl   <= s_axil_wdata;
                default: ;
            endcase
            axil_bvalid_r <= 1'b1;
            axil_bresp_r  <= 2'b00;
        end else if (s_axil_bready)
            axil_bvalid_r <= 1'b0;
    end
end

always @(posedge clk) begin
    if (!resetn) begin
        axil_arready_r <= 1'b0;
        axil_rvalid_r  <= 1'b0;
        axil_rdata_r   <= 32'd0;
        axil_rresp_r   <= 2'b00;
    end else begin
        if (s_axil_arvalid && ~axil_arready_r) begin
            axil_arready_r <= 1'b1;
            axil_rresp_r   <= 2'b00;
            axil_rvalid_r  <= 1'b1;
            case (s_axil_araddr[3:2])
                2'b00: axil_rdata_r <= reg_nco_freq;
                2'b01: axil_rdata_r <= {25'd0, reg_interp_rate};
                2'b10: axil_rdata_r <= reg_dac_ctrl;
                default: axil_rdata_r <= 32'd0;
            endcase
        end else
            axil_arready_r <= 1'b0;
        if (axil_rvalid_r && s_axil_rready)
            axil_rvalid_r <= 1'b0;
    end
end

// ============================================================
// AXI-Stream input: unpack I/Q, backpressure = always ready
// ============================================================
assign s_axis_tready = 1'b1;

wire signed [15:0] axis_I = s_axis_tdata[15:0];
wire signed [15:0] axis_Q = s_axis_tdata[31:16];
wire               axis_valid = s_axis_tvalid;

// ============================================================
// HB FIR interpolators I/Q (p.1.5 hb_fir_interpolator.v)
// Input @ fs_cic/2, output @ fs_cic
// ============================================================
wire [15:0] hb_I_out, hb_Q_out;
wire        hb_I_valid, hb_Q_valid;

hb_fir_interpolator u_hb_I (
    .clk           (clk),
    .resetn        (resetn),
    .din           (axis_I),
    .din_valid     (axis_valid),
    .dout          (hb_I_out),
    .dout_valid    (hb_I_valid),
    .s_axil_awaddr (6'd0), .s_axil_awvalid(1'b0),
    .s_axil_awready(), .s_axil_wdata(32'd0), .s_axil_wvalid(1'b0),
    .s_axil_wready(), .s_axil_bresp(), .s_axil_bvalid(),
    .s_axil_bready(1'b1), .s_axil_araddr(6'd0), .s_axil_arvalid(1'b0),
    .s_axil_arready(), .s_axil_rdata(), .s_axil_rresp(),
    .s_axil_rvalid(), .s_axil_rready(1'b1)
);

hb_fir_interpolator u_hb_Q (
    .clk           (clk),
    .resetn        (resetn),
    .din           (axis_Q),
    .din_valid     (axis_valid),
    .dout          (hb_Q_out),
    .dout_valid    (hb_Q_valid),
    .s_axil_awaddr (6'd0), .s_axil_awvalid(1'b0),
    .s_axil_awready(), .s_axil_wdata(32'd0), .s_axil_wvalid(1'b0),
    .s_axil_wready(), .s_axil_bresp(), .s_axil_bvalid(),
    .s_axil_bready(1'b1), .s_axil_araddr(6'd0), .s_axil_arvalid(1'b0),
    .s_axil_arready(), .s_axil_rdata(), .s_axil_rresp(),
    .s_axil_rvalid(), .s_axil_rready(1'b1)
);

// ============================================================
// CIC interpolators I/Q (p.1.5 cic_interpolator.v)
// Rate from register bank; AXI-Lite tied off (rate set internally)
// ============================================================
wire [15:0] cic_I_out, cic_Q_out;
wire        cic_I_valid, cic_Q_valid;

cic_interpolator u_cic_I (
    .clk           (clk),
    .resetn        (resetn),
    .din           (hb_I_out),
    .din_valid     (hb_I_valid),
    .dout          (cic_I_out),
    .dout_valid    (cic_I_valid),
    .s_axil_awaddr (4'd0), .s_axil_awvalid(1'b0),
    .s_axil_awready(), .s_axil_wdata(32'd0), .s_axil_wvalid(1'b0),
    .s_axil_wready(), .s_axil_bresp(), .s_axil_bvalid(),
    .s_axil_bready(1'b1), .s_axil_araddr(4'd0), .s_axil_arvalid(1'b0),
    .s_axil_arready(), .s_axil_rdata(), .s_axil_rresp(),
    .s_axil_rvalid(), .s_axil_rready(1'b1)
);

cic_interpolator u_cic_Q (
    .clk           (clk),
    .resetn        (resetn),
    .din           (hb_Q_out),
    .din_valid     (hb_Q_valid),
    .dout          (cic_Q_out),
    .dout_valid    (cic_Q_valid),
    .s_axil_awaddr (4'd0), .s_axil_awvalid(1'b0),
    .s_axil_awready(), .s_axil_wdata(32'd0), .s_axil_wvalid(1'b0),
    .s_axil_wready(), .s_axil_bresp(), .s_axil_bvalid(),
    .s_axil_bready(1'b1), .s_axil_araddr(4'd0), .s_axil_arvalid(1'b0),
    .s_axil_arready(), .s_axil_rdata(), .s_axil_rresp(),
    .s_axil_rvalid(), .s_axil_rready(1'b1)
);

// ============================================================
// NCO — shared with DDC (nco_direct, freq_word from register bank)
// ============================================================
wire [17:0] nco_sin, nco_cos;
wire        nco_valid;

nco_direct u_nco (
    .clk      (clk),
    .resetn   (resetn),
    .freq_word(reg_nco_freq),
    .sin_out  (nco_sin),
    .cos_out  (nco_cos),
    .valid_out(nco_valid)
);

// ============================================================
// Complex mixer — DUC mode: out = I*cos - Q*sin (real -> DAC)
// I_in/Q_in: 13-bit; cic outputs 16-bit -> truncate [15:3]
// ============================================================
wire [13:0] duc_out;
wire        mix_valid;

complex_mixer u_mixer (
    .clk      (clk),
    .resetn   (resetn),
    .duc_mode (1'b1),
    .data_in  (12'd0),
    .I_in     (cic_I_out[15:3]),
    .Q_in     (cic_Q_out[15:3]),
    .sin_in   (nco_sin),
    .cos_in   (nco_cos),
    .nco_valid(nco_valid & cic_I_valid & cic_Q_valid),
    .I_out    (),
    .Q_out    (),
    .duc_out  (duc_out),
    .valid_out(mix_valid)
);

// ============================================================
// DAC test mode (reg_dac_ctrl[4]): drive DAC directly with offset-binary
// cosine from the NCO. Bypasses the DMA/HB/CIC/mixer path so we can
// stimulate the ADC via loopback. NCO frequency = whatever DUC NCO is
// set to. Scale nco_cos (signed 18-bit, ±131071) into 14-bit offset
// binary by inverting MSB after truncation: midscale = 0x2000.
// ============================================================
wire        dac_test_mode = reg_dac_ctrl[4];
wire [13:0] dac_test_cos  = {~nco_cos[17], nco_cos[16:4]};
wire [13:0] dac_mux_data  = dac_test_mode ? dac_test_cos : duc_out;
wire        dac_mux_valid = dac_test_mode ? nco_valid   : mix_valid;

// ============================================================
// DAC interface (p.1.3 dac_if.v)
// AXI-Lite: PD control from reg_dac_ctrl
// ============================================================
dac_if u_dac_if (
    .s_axis_aclk    (clk),
    .s_axis_aresetn (resetn),
    .s_axis_tdata   ({2'b00, dac_mux_data}),
    .s_axis_tvalid  (dac_mux_valid),
    .s_axis_tready  (),
    .s_axil_awaddr  (4'd0), .s_axil_awvalid(1'b0),
    .s_axil_awready(), .s_axil_wdata(32'd0), .s_axil_wvalid(1'b0),
    .s_axil_wready(), .s_axil_bresp(), .s_axil_bvalid(),
    .s_axil_bready(1'b1), .s_axil_araddr(4'd0), .s_axil_arvalid(1'b0),
    .s_axil_arready(), .s_axil_rdata(), .s_axil_rresp(),
    .s_axil_rvalid(), .s_axil_rready(1'b1),
    .DAC     (DAC),
    .CLK_DAC (CLK_DAC),
    .PD      (PD)
);

endmodule
