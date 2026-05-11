// hardware/rtl/ddc_top.v
// DDC top: adc_if -> complex_mixer (NCO) -> cic_decimator -> hb_fir_decimator -> AXI-Stream I/Q
// AXI-Lite register map (single control block):
//   0x00: nco_freq_word[31:0]
//   0x04: decimation_rate[7:0]  (15/30/60/120)
//   0x08: status[31:0]          {30'b0, lock, overflow}
//   0x0C: samples_per_packet[31:0] — count of output beats per TLAST burst

`timescale 1ns/1ps

module ddc_top #(
    parameter AXI_ADDR_WIDTH = 4
)(
    input  wire        clk,          // 60 MHz
    input  wire        resetn,

    // ADC physical pins
    input  wire [11:0] ADC,          // AD9226 data
    input  wire        OTR,          // out-of-range

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

    // AXI-Stream I/Q output
    output wire [31:0] m_axis_tdata,  // [31:16]=Q, [15:0]=I (16-bit signed)
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready
);

// ============================================================
// AXI-Lite: single register bank
// ============================================================
reg [31:0] reg_nco_freq;          // 0x00
reg [6:0]  reg_dec_rate;          // 0x04 [6:0]
reg [31:0] reg_status;            // 0x08, RO
reg [31:0] reg_samples_per_packet; // 0x0C, default 4096

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
        reg_nco_freq           <= 32'd0;
        reg_dec_rate           <= 7'd30;
        reg_samples_per_packet <= 32'd4096;
        axil_awready_r <= 1'b0;
        axil_wready_r  <= 1'b0;
        axil_bvalid_r  <= 1'b0;
        axil_bresp_r   <= 2'b00;
    end else begin
        axil_awready_r <= s_axil_awvalid & s_axil_wvalid & ~axil_awready_r;
        axil_wready_r  <= s_axil_awvalid & s_axil_wvalid & ~axil_wready_r;
        if (s_axil_awvalid && s_axil_wvalid && axil_awready_r && axil_wready_r) begin
            case (s_axil_awaddr[3:2])
                2'b00: reg_nco_freq           <= s_axil_wdata;
                2'b01: reg_dec_rate           <= s_axil_wdata[6:0];
                2'b11: reg_samples_per_packet <= s_axil_wdata;
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
                2'b01: axil_rdata_r <= {25'd0, reg_dec_rate};
                2'b10: axil_rdata_r <= reg_status;
                2'b11: axil_rdata_r <= reg_samples_per_packet;
                default: axil_rdata_r <= 32'd0;
            endcase
        end else
            axil_arready_r <= 1'b0;
        if (axil_rvalid_r && s_axil_rready)
            axil_rvalid_r <= 1'b0;
    end
end

// ============================================================
// ADC interface (p.1.4)
// ============================================================
wire [15:0] adc_tdata;
wire        adc_tvalid;
wire        adc_totr;

adc_if u_adc_if (
    .CLK_ADC      (clk),
    .ADC          (ADC),
    .OTR          (OTR),
    .m_axis_tdata (adc_tdata),
    .m_axis_tvalid(adc_tvalid),
    .m_axis_totr  (adc_totr),
    .m_axis_tready(1'b1)
);

// ============================================================
// NCO (p.1.8) — freq_word from register bank
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
// Complex mixer (p.1.6) — DDC mode
// ============================================================
wire [12:0] mix_I, mix_Q;
wire        mix_valid;

complex_mixer u_mixer (
    .clk      (clk),
    .resetn   (resetn),
    .duc_mode (1'b0),
    .data_in  (adc_tdata[11:0]),
    .I_in     (13'd0),
    .Q_in     (13'd0),
    .sin_in   (nco_sin),
    .cos_in   (nco_cos),
    .nco_valid(nco_valid & adc_tvalid),
    .I_out    (mix_I),
    .Q_out    (mix_Q),
    .duc_out  (),
    .valid_out(mix_valid)
);

// ============================================================
// CIC decimators I/Q (p.1.7) — rate from register bank
// ============================================================
wire [15:0] cic_I_out, cic_Q_out;
wire        cic_I_valid, cic_Q_valid;

cic_decimator u_cic_I (
    .clk         (clk),
    .resetn      (resetn),
    .din         (mix_I),
    .din_valid   (mix_valid),
    .decimation_r(reg_dec_rate),
    .dout        (cic_I_out),
    .dout_valid  (cic_I_valid)
);

cic_decimator u_cic_Q (
    .clk         (clk),
    .resetn      (resetn),
    .din         (mix_Q),
    .din_valid   (mix_valid),
    .decimation_r(reg_dec_rate),
    .dout        (cic_Q_out),
    .dout_valid  (cic_Q_valid)
);

// ============================================================
// HB FIR decimators I/Q (p.1.7)
// ============================================================
wire [15:0] hb_I_out, hb_Q_out;
wire        hb_I_valid, hb_Q_valid;

hb_fir_decimator u_hb_I (
    .clk           (clk),
    .resetn        (resetn),
    .din           (cic_I_out),
    .din_valid     (cic_I_valid),
    .dout          (hb_I_out),
    .dout_valid    (hb_I_valid),
    .s_axil_awaddr (6'd0), .s_axil_awvalid(1'b0),
    .s_axil_awready(), .s_axil_wdata(32'd0), .s_axil_wvalid(1'b0),
    .s_axil_wready(), .s_axil_bresp(), .s_axil_bvalid(),
    .s_axil_bready(1'b1), .s_axil_araddr(6'd0), .s_axil_arvalid(1'b0),
    .s_axil_arready(), .s_axil_rdata(), .s_axil_rresp(),
    .s_axil_rvalid(), .s_axil_rready(1'b1)
);

hb_fir_decimator u_hb_Q (
    .clk           (clk),
    .resetn        (resetn),
    .din           (cic_Q_out),
    .din_valid     (cic_Q_valid),
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
// Status register: bit0 overflow (sticky OTR), bit1 lock (sticky — set
// once first hb_I sample appears so a polled read doesn't miss it).
// ============================================================
reg overflow_sticky;
reg lock_sticky;
always @(posedge clk) begin
    if (!resetn) begin
        overflow_sticky <= 1'b0;
        lock_sticky     <= 1'b0;
    end else begin
        if (adc_totr & adc_tvalid)
            overflow_sticky <= 1'b1;
        if (hb_I_valid & hb_Q_valid)
            lock_sticky     <= 1'b1;
    end
end

always @(posedge clk) begin
    if (!resetn)
        reg_status <= 32'd0;
    else
        reg_status <= {30'd0, lock_sticky, overflow_sticky};
end

// ============================================================
// AXI-Stream I/Q output: pack [31:16]=Q, [15:0]=I
// TLAST asserted on every (samples_per_packet)-th accepted beat — required
// by AXI DMA in direct-register (non-SG) mode to signal end-of-buffer.
// ============================================================
reg  [31:0] sample_counter;
wire        axis_handshake = (hb_I_valid & hb_Q_valid) & m_axis_tready;

always @(posedge clk) begin
    if (!resetn)
        sample_counter <= 32'd0;
    else if (axis_handshake) begin
        if (sample_counter == reg_samples_per_packet - 32'd1)
            sample_counter <= 32'd0;
        else
            sample_counter <= sample_counter + 32'd1;
    end
end

assign m_axis_tdata  = {hb_Q_out, hb_I_out};
assign m_axis_tvalid = hb_I_valid & hb_Q_valid;
assign m_axis_tlast  = axis_handshake &&
                       (sample_counter == reg_samples_per_packet - 32'd1);

endmodule

// ============================================================
// nco_direct: NCO с прямым портом freq_word (без AXI-Lite)
// ============================================================
module nco_direct (
    input  wire        clk,
    input  wire        resetn,
    input  wire [31:0] freq_word,
    output reg  [17:0] sin_out,
    output reg  [17:0] cos_out,
    output reg         valid_out
);
    reg [31:0] phase_acc;
    always @(posedge clk) begin
        if (!resetn) phase_acc <= 32'd0;
        else         phase_acc <= phase_acc + freq_word;
    end

    wire [9:0] lut_addr = phase_acc[31:22];

    (* rom_style = "block" *)
    reg [35:0] sincos_lut [0:1023]; // [35:18]=cos, [17:0]=sin
    // Vivado synth drops $sin/$cos in initial blocks (warning Synth 8-311,
    // "ignoring non-constant assignment in initial block"). The result is
    // a LUT with no driver — reads return 0 forever, so the NCO outputs
    // zero, and the whole DDC/DUC datapath multiplies by zero.
    // Inline 1024 precomputed constants instead. Regenerate the include
    // file via tools/gen_nco_lut.py if the LUT depth/scale ever changes.
    initial begin
        `include "nco_lut_init.vh"
    end

    reg [9:0] lut_addr_r;
    always @(posedge clk) begin
        if (!resetn) begin
            lut_addr_r <= 10'd0;
            sin_out    <= 18'd0;
            cos_out    <= 18'd0;
            valid_out  <= 1'b0;
        end else begin
            lut_addr_r <= lut_addr;
            sin_out    <= sincos_lut[lut_addr_r][17:0];
            cos_out    <= sincos_lut[lut_addr_r][35:18];
            valid_out  <= 1'b1;
        end
    end
endmodule
