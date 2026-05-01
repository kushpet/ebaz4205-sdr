// hardware/rtl/sdr_top.v
// Toplevel wrapper around the BD's system_wrapper.
// Most of the integration (MMCM, PS7, DMA, DDC/DUC) lives inside the BD —
// see hardware/scripts/create_bd.tcl. This file only forwards physical pins
// and adds two pieces that don't belong in a Block Design:
//   - the AD9226 sample-clock pin (CLK_ADC) driven via ODDR for clean edges;
//   - the user LEDs heart-beat for board sanity.

`timescale 1ns/1ps

module sdr_top (
    // ADC interface (DATA3)
    input  wire [11:0] ADC,
    input  wire        OTR,
    output wire        CLK_ADC,         // FPGA drives 60 MHz to AD9226 (pin M19)

    // DAC interface (DATA1/DATA2)
    output wire [13:0] DAC,
    output wire        CLK_DAC,
    output wire        PD,

    // PHY refclk (IP101G XI)
    output wire        PHY_REFCLK_25MHZ,

    // User LEDs
    output wire        LED_GREEN,
    output wire        LED_RED
);

// ============================================================
// Clocks coming out of the BD wrapper
// ============================================================
wire clk_60mhz;
wire clk_25mhz;
wire mmcm_locked;
wire fclk_resetn;

// ============================================================
// BD wrapper instance
// (system_wrapper is auto-generated from create_bd.tcl)
//
// External pins exposed by the BD (see create_bd.tcl):
//   ADC_0, OTR_0                        : DDC inputs
//   DAC_0, CLK_DAC_0, PD_0              : DUC outputs
//   clk_60mhz_0, clk_25mhz_0, locked_0  : MMCM outputs
//   FCLK_RESET0_N_0                     : PS reset
// ============================================================
system_wrapper u_system (
    .ADC_0            (ADC),
    .OTR_0            (OTR),
    .DAC_0            (DAC),
    .CLK_DAC_0        (CLK_DAC),
    .PD_0             (PD),

    .clk_60mhz_0      (clk_60mhz),
    .clk_25mhz_0      (clk_25mhz),
    .mmcm_locked_0    (mmcm_locked),
    .fclk_resetn_0    (fclk_resetn)
);

// PHY refclk to U18: clean BUFG already inside the BD's MMCM wrapper.
assign PHY_REFCLK_25MHZ = clk_25mhz;

// ============================================================
// Drive AD9226 sample clock through ODDR for matched edge alignment
// (output toggles between D1=1 on rising clk and D2=0 on falling clk,
//  giving a clean 60 MHz square wave with no clock-tree skew).
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
