// AD9226 parallel ADC interface → AXI-Stream
// ADC[0](N20)=BIT12/LSB .. ADC[11](U20)=BIT1/MSB, twos complement (MODE=GND)
// AD9226 Tpd: 3.5..7 ns, CLK 60 MHz (period 16.67 ns) → posedge capture is safe

module adc_if (
    input  wire        CLK_ADC,      // 60 MHz, pin M19
    input  wire [11:0] ADC,          // ADC[0]=LSB(N20) .. ADC[11]=MSB(U20)
    input  wire        OTR,          // Out-of-Range, pin V20

    output reg  [15:0] m_axis_tdata, // sign-extended 12→16 bit (twos complement)
    output reg         m_axis_tvalid,
    output reg         m_axis_totr,  // OTR, pipeline-aligned with tdata
    input  wire        m_axis_tready
);

    // ADC[11]=MSB, ADC[0]=LSB → sign-extend from bit 11
    always @(posedge CLK_ADC) begin
        m_axis_tdata  <= {{4{ADC[11]}}, ADC};
        m_axis_totr   <= OTR;
        m_axis_tvalid <= 1'b1;
    end

endmodule
