// hardware/rtl/sdr_top.v
// Toplevel: forwards physical pins to/from the BD's system_wrapper.
// All real integration (PS7, MMCM via clk_wiz, AXI DMA, DDC/DUC,
// AXI Interconnect) lives inside the BD — see hardware/scripts/create_bd.tcl.
//
// This file:
//   - passes the PS7 DDR / FIXED_IO inout buses through unchanged;
//   - drives the AD9226 sample clock (CLK_ADC pin M19) from the BD's
//     60 MHz output via an ODDR for matched edge alignment;
//   - exposes the BD's 25 MHz output as PHY_REFCLK_25MHZ (pin U18);
//   - exposes a heartbeat on LED_GREEN/LED_RED.

`timescale 1ns/1ps

module sdr_top (
    // ADC interface (DATA3)
    input  wire [11:0] ADC,
    input  wire        OTR,
    output wire        CLK_ADC,                 // FPGA drives 60 MHz to AD9226 (pin M19)

    // DAC interface (DATA1/DATA2)
    output wire [13:0] DAC,
    output wire        CLK_DAC,
    output wire        PD,

    // PHY refclk (IP101G XI)
    output wire        PHY_REFCLK_25MHZ,        // pin U18

    // User LEDs
    output wire        LED_GREEN,
    output wire        LED_RED,

    // PS7 DDR pins (passed straight through to package)
    inout  wire [14:0] DDR_addr,
    inout  wire [ 2:0] DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [ 3:0] DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [ 3:0] DDR_dqs_n,
    inout  wire [ 3:0] DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,

    // PS7 FIXED_IO
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb
);

// ============================================================
// Clocks coming out of the BD wrapper
// ============================================================
wire clk_60mhz;
wire clk_25mhz;
wire mmcm_locked;
wire fclk_resetn;

// ============================================================
// BD wrapper instance — port names follow create_bd.tcl
// ============================================================
system_wrapper u_system (
    // ADC / DAC
    .ADC_0            (ADC),
    .OTR_0            (OTR),
    .DAC_0            (DAC),
    .CLK_DAC_0        (CLK_DAC),
    .PD_0             (PD),

    // Clocks / status
    .clk_60mhz_0      (clk_60mhz),
    .clk_25mhz_0      (clk_25mhz),
    .mmcm_locked_0    (mmcm_locked),
    .fclk_resetn_0    (fclk_resetn),

    // PS DDR
    .DDR_addr         (DDR_addr),
    .DDR_ba           (DDR_ba),
    .DDR_cas_n        (DDR_cas_n),
    .DDR_ck_n         (DDR_ck_n),
    .DDR_ck_p         (DDR_ck_p),
    .DDR_cke          (DDR_cke),
    .DDR_cs_n         (DDR_cs_n),
    .DDR_dm           (DDR_dm),
    .DDR_dq           (DDR_dq),
    .DDR_dqs_n        (DDR_dqs_n),
    .DDR_dqs_p        (DDR_dqs_p),
    .DDR_odt          (DDR_odt),
    .DDR_ras_n        (DDR_ras_n),
    .DDR_reset_n      (DDR_reset_n),
    .DDR_we_n         (DDR_we_n),

    // PS FIXED_IO
    .FIXED_IO_ddr_vrn (FIXED_IO_ddr_vrn),
    .FIXED_IO_ddr_vrp (FIXED_IO_ddr_vrp),
    .FIXED_IO_mio     (FIXED_IO_mio),
    .FIXED_IO_ps_clk  (FIXED_IO_ps_clk),
    .FIXED_IO_ps_porb (FIXED_IO_ps_porb),
    .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb)
);

// PHY refclk passes the BD's 25 MHz BUFG output straight to U18.
assign PHY_REFCLK_25MHZ = clk_25mhz;

// ============================================================
// Drive AD9226 sample clock through ODDR for matched edge alignment.
// D1 captured on rising clk, D2 on falling clk → clean 60 MHz square wave.
// ============================================================
ODDR #(
    .DDR_CLK_EDGE ("OPPOSITE_EDGE"),
    .INIT         (1'b0),
    .SRTYPE       ("SYNC")
) oddr_clk_adc (
    .Q  (CLK_ADC),
    .C  (clk_60mhz),
    .CE (1'b1),
    .D1 (1'b1),
    .D2 (1'b0),
    .R  (1'b0),
    .S  (1'b0)
);

// ============================================================
// LED status: GREEN ~1 Hz blink while locked, RED solid on fault
// ============================================================
reg [25:0] led_div;
always @(posedge clk_60mhz or negedge fclk_resetn) begin
    if (!fclk_resetn) led_div <= 26'd0;
    else              led_div <= led_div + 26'd1;
end

assign LED_GREEN = mmcm_locked  ? led_div[25] : 1'b0;
assign LED_RED   = ~mmcm_locked;

endmodule
