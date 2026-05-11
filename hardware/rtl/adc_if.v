// AD9226 parallel ADC interface → AXI-Stream
// ADC[0](N20)=BIT12/LSB .. ADC[11](U20)=BIT1/MSB
// AD9226 Tpd: 3.5..7 ns, CLK 60 MHz (period 16.67 ns) → posedge capture is safe
//
// The LQFP-48 daughter card straps MODE/DFS so the AD9226 outputs *straight
// binary* (midscale = 0x800), not twos-complement. We convert here by
// inverting the MSB before sign-extension — equivalent to subtracting 0x800.
// Diagnostic that confirmed straight binary: with no input, MSB toggles on
// nearly every sample (would stay constant under twos-comp), and the DDC
// output averaged to ≈0 because the wrong sign-extension produced ±2048
// alternations that CIC then averaged out.

module adc_if (
    input  wire        CLK_ADC,      // 60 MHz, pin M19
    input  wire [11:0] ADC,          // ADC[0]=LSB(N20) .. ADC[11]=MSB(U20)
    input  wire        OTR,          // Out-of-Range, pin V20

    output reg  [15:0] m_axis_tdata, // sign-extended 12→16 bit (twos complement)
    output reg         m_axis_tvalid,
    output reg         m_axis_totr,  // OTR, pipeline-aligned with tdata
    input  wire        m_axis_tready
);

    // Straight binary → twos-complement: invert MSB, then sign-extend.
    // Input  0x000 (-FS) → 0x800 → sign-ext 0xF800 = -2048
    // Input  0x800 ( 0 ) → 0x000 → sign-ext 0x0000 =  0
    // Input  0xFFF (+FS) → 0x7FF → sign-ext 0x07FF = +2047
    always @(posedge CLK_ADC) begin
        m_axis_tdata  <= {{5{~ADC[11]}}, ADC[10:0]};
        m_axis_totr   <= OTR;
        m_axis_tvalid <= 1'b1;
    end

endmodule
