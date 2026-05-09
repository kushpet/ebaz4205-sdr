// hardware/sim/tb_ddc_full.v
// Drive ddc_top with a constant ADC input and probe both the CIC's
// dout and the final m_axis to see where saturation first appears.

`timescale 1ns/1ps

module tb_ddc_full;

reg               clk    = 0;
reg               resetn = 0;
reg [11:0]        ADC    = 12'd0;
reg               OTR    = 1'b0;
wire [31:0]       m_axis_tdata;
wire              m_axis_tvalid;

always #8 clk = ~clk;

ddc_top #(.AXI_ADDR_WIDTH(4)) u_dut (
    .clk(clk), .resetn(resetn),
    .ADC(ADC), .OTR(OTR),
    .s_axil_awaddr(4'd0), .s_axil_awvalid(1'b0), .s_axil_awready(),
    .s_axil_wdata(32'd0), .s_axil_wvalid(1'b0), .s_axil_wready(),
    .s_axil_bresp(), .s_axil_bvalid(), .s_axil_bready(1'b1),
    .s_axil_araddr(4'd0), .s_axil_arvalid(1'b0), .s_axil_arready(),
    .s_axil_rdata(), .s_axil_rresp(), .s_axil_rvalid(),
    .s_axil_rready(1'b1),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tlast(),
    .m_axis_tready(1'b1)
);

// Hierarchical probes into the CIC dout (16-bit) and HB FIR I dout (16-bit).
wire signed [15:0] cic_I_dout = u_dut.cic_I_out;
wire signed [15:0] cic_Q_dout = u_dut.cic_Q_out;
wire signed [15:0] hb_I_dout  = u_dut.hb_I_out;
wire signed [15:0] hb_Q_dout  = u_dut.hb_Q_out;

initial begin
    #100 resetn = 1;

    // Run each input long enough to fully settle (CIC + HB FIR transient).
    repeat (4000) @(posedge clk);
    $display("\n=== ADC=0x000 (zero, settled) ===");
    $display("  cic_I=%6d  cic_Q=%6d  hb_I=%6d  hb_Q=%6d  m_axis=%08h",
             cic_I_dout, cic_Q_dout, hb_I_dout, hb_Q_dout, m_axis_tdata);

    ADC = 12'hFFF;
    repeat (50000) @(posedge clk);
    $display("\n=== ADC=0xFFF (-1, settled) ===");
    $display("  cic_I=%6d  cic_Q=%6d  hb_I=%6d  hb_Q=%6d  m_axis=%08h",
             cic_I_dout, cic_Q_dout, hb_I_dout, hb_Q_dout, m_axis_tdata);

    ADC = 12'h800;
    repeat (50000) @(posedge clk);
    $display("\n=== ADC=0x800 (-2048, settled) ===");
    $display("  cic_I=%6d  cic_Q=%6d  hb_I=%6d  hb_Q=%6d  m_axis=%08h",
             cic_I_dout, cic_Q_dout, hb_I_dout, hb_Q_dout, m_axis_tdata);

    ADC = 12'h7FF;
    repeat (50000) @(posedge clk);
    $display("\n=== ADC=0x7FF (+2047, settled) ===");
    $display("  cic_I=%6d  cic_Q=%6d  hb_I=%6d  hb_Q=%6d  m_axis=%08h",
             cic_I_dout, cic_Q_dout, hb_I_dout, hb_Q_dout, m_axis_tdata);

    ADC = 12'h000;
    repeat (50000) @(posedge clk);
    $display("\n=== ADC=0x000 (back to zero, settled) ===");
    $display("  cic_I=%6d  cic_Q=%6d  hb_I=%6d  hb_Q=%6d  m_axis=%08h",
             cic_I_dout, cic_Q_dout, hb_I_dout, hb_Q_dout, m_axis_tdata);

    $finish;
end

initial begin
    #100000000 $display("WATCHDOG"); $finish;
end

endmodule
