// hardware/sim/tb_hb_fir.v
// Quick standalone test of hb_fir_decimator with constant input.
// Drives din = 0 and observes whether dout settles to 0 or to -32768
// (the saturation pin we see on real hardware).

`timescale 1ns/1ps

module tb_hb_fir;

reg               clk    = 0;
reg               resetn = 0;
reg signed [15:0] din    = 16'd0;
reg               din_valid = 0;
wire       [15:0] dout;
wire              dout_valid;

always #5 clk = ~clk;  // 100 MHz

hb_fir_decimator u_dut (
    .clk(clk), .resetn(resetn),
    .din(din), .din_valid(din_valid),
    .dout(dout), .dout_valid(dout_valid),
    .s_axil_awaddr(6'd0), .s_axil_awvalid(1'b0), .s_axil_awready(),
    .s_axil_wdata(32'd0), .s_axil_wvalid(1'b0), .s_axil_wready(),
    .s_axil_bresp(), .s_axil_bvalid(), .s_axil_bready(1'b1),
    .s_axil_araddr(6'd0), .s_axil_arvalid(1'b0), .s_axil_arready(),
    .s_axil_rdata(), .s_axil_rresp(), .s_axil_rvalid(),
    .s_axil_rready(1'b1)
);

integer out_count = 0;

// no per-change print; testbench prints settled state explicitly

initial begin
    #100 resetn = 1;
    @(posedge clk);

    $display("=== din = 0 ===");
    din = 16'd0;
    forever @(posedge clk) din_valid = 1;
end

task report(input [15:0] label_din);
    $display("din=%6d sr[0]=%6d sr[31]=%6d sr[62]=%6d ch=%6d prod[0]=%0d prod[15]=%0d acc=%0d rh=%0d dout=%6d",
             $signed(label_din),
             $signed(u_dut.sr[0]),  $signed(u_dut.sr[31]),
             $signed(u_dut.sr[62]),
             $signed(u_dut.center_half_q),
             $signed(u_dut.prod[0]),  $signed(u_dut.prod[15]),
             $signed(u_dut.acc), $signed(u_dut.rounded_hi),
             $signed(dout));
endtask

initial begin
    repeat (300) @(posedge clk);
    $display("\n=== din = 0 (settled) ==="); report(din);

    @(posedge clk) din = -16'sd1;
    repeat (300) @(posedge clk);
    $display("\n=== din = -1 (settled) ==="); report(din);

    @(posedge clk) din = 16'sd1;
    repeat (300) @(posedge clk);
    $display("\n=== din = +1 (settled) ==="); report(din);

    @(posedge clk) din = -16'sd6;
    repeat (300) @(posedge clk);
    $display("\n=== din = -6 (settled) ==="); report(din);

    @(posedge clk) din = 16'sd5;
    repeat (300) @(posedge clk);
    $display("\n=== din = +5 (settled) ==="); report(din);

    $finish;
end

initial begin
    #100000 $display("WATCHDOG"); $finish;
end

endmodule
