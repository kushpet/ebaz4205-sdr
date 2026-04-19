// hardware/rtl/clk_60mhz.v
// MMCM wrapper: FCLK_CLK0 (100 MHz) -> clk_60mhz, clk_25mhz
// VCO = 100 * 6.0 / 1 = 600 MHz
// CLKOUT0 = 600/10.0 = 60 MHz (ADC/DAC/PL)
// CLKOUT1 = 600/24   = 25 MHz (IP101G U18)

module clk_60mhz (
    input  wire clk_in,    // FCLK_CLK0 100 MHz from PS7
    input  wire reset,
    output wire clk_60mhz,
    output wire clk_25mhz,
    output wire locked
);

wire clkfb;
wire clkfb_buf;
wire clk60_raw;
wire clk25_raw;

MMCME2_ADV #(
    .BANDWIDTH            ("OPTIMIZED"),
    .CLKFBOUT_MULT_F      (6.0),
    .CLKFBOUT_PHASE       (0.0),
    .CLKIN1_PERIOD        (10.0),   // 100 MHz = 10 ns
    .CLKOUT0_DIVIDE_F     (10.0),   // 60 MHz
    .CLKOUT0_DUTY_CYCLE   (0.5),
    .CLKOUT0_PHASE        (0.0),
    .CLKOUT1_DIVIDE       (24),     // 25 MHz
    .CLKOUT1_DUTY_CYCLE   (0.5),
    .CLKOUT1_PHASE        (0.0),
    .DIVCLK_DIVIDE        (1),
    .REF_JITTER1          (0.01),
    .STARTUP_WAIT         ("FALSE"),
    .COMPENSATION         ("ZHOLD")
) mmcm_inst (
    .CLKIN1    (clk_in),
    .CLKIN2    (1'b0),
    .CLKINSEL  (1'b1),
    .RST       (reset),
    .PWRDWN    (1'b0),
    .LOCKED    (locked),
    .CLKFBOUT  (clkfb),
    .CLKFBIN   (clkfb_buf),
    .CLKOUT0   (clk60_raw),
    .CLKOUT1   (clk25_raw),
    // unused outputs
    .CLKOUT0B  (),
    .CLKOUT1B  (),
    .CLKOUT2   (), .CLKOUT2B  (),
    .CLKOUT3   (), .CLKOUT3B  (),
    .CLKOUT4   (),
    .CLKOUT5   (),
    .CLKOUT6   (),
    .CLKFBOUTB (),
    .CLKFBSTOPPED (),
    .CLKINSTOPPED (),
    .DO        (), .DRDY      (),
    .DADDR     (7'h0), .DCLK (1'b0), .DEN (1'b0),
    .DI        (16'h0), .DWE (1'b0),
    .PSCLK     (1'b0), .PSEN (1'b0),
    .PSINCDEC  (1'b0), .PSDONE ()
);

BUFG bufg_fb   (.I(clkfb),     .O(clkfb_buf));
BUFG bufg_60   (.I(clk60_raw), .O(clk_60mhz));
BUFG bufg_25   (.I(clk25_raw), .O(clk_25mhz));

endmodule
