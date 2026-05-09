// hardware/sim/tb_cic_zero.v
// Drive cic_decimator with constant 0 input and observe dout.
// Theory: dout should settle to 0. If it produces 0x8000, we've
// found the bug.

`timescale 1ns/1ps

module tb_cic_zero;

reg               clk    = 0;
reg               resetn = 0;
reg signed [12:0] din    = 13'd0;
reg               din_valid = 0;
reg        [6:0]  decimation_r = 7'd30;
wire       [15:0] dout;
wire              dout_valid;

always #5 clk = ~clk;

cic_decimator u_dut (
    .clk(clk), .resetn(resetn),
    .din(din), .din_valid(din_valid),
    .decimation_r(decimation_r),
    .dout(dout), .dout_valid(dout_valid)
);

integer out_count = 0;

always @(posedge clk) begin
    if (dout_valid) begin
        $display("t=%0t  dout=%6d  (0x%04h)", $time, $signed(dout), dout);
        out_count = out_count + 1;
        if (out_count >= 12) $finish;
    end
end

initial begin
    #100 resetn = 1;
    forever @(posedge clk) din_valid = 1;
end

initial begin
    #1000000 $display("WATCHDOG: only %0d outputs", out_count); $finish;
end

endmodule
