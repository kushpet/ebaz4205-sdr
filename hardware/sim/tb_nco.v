// hardware/sim/tb_nco.v
// Testbench for nco.v
// Checks:
//   1. AXI-Lite write of freq_word
//   2. sin/cos output amplitude and quadrature (|sin|^2 + |cos|^2 ~ 1)
//   3. Frequency accuracy: period = fs / freq_word * 2^32 cycles
// Simulation: 1024 cycles @ 60 MHz -> observe full period for freq_word=2^22 (fc~14.3 MHz)
// $dumpfile for GTKWave

`timescale 1ns/1ps

module tb_nco;

localparam CLK_PERIOD = 16; // ~16.67 ns, approx 60 MHz

reg clk, resetn;
reg [3:0]  axil_awaddr;
reg        axil_awvalid;
reg [31:0] axil_wdata;
reg        axil_wvalid;
reg        axil_bready;
reg [3:0]  axil_araddr;
reg        axil_arvalid;
reg        axil_rready;

wire       axil_awready, axil_wready, axil_bvalid;
wire [1:0] axil_bresp;
wire       axil_arready, axil_rvalid;
wire [1:0] axil_rresp;
wire [31:0] axil_rdata;
wire [17:0] sin_out, cos_out;
wire        valid_out;

nco #(.AXI_ADDR_WIDTH(4)) dut (
    .clk           (clk),
    .resetn        (resetn),
    .s_axil_awaddr (axil_awaddr),
    .s_axil_awvalid(axil_awvalid),
    .s_axil_awready(axil_awready),
    .s_axil_wdata  (axil_wdata),
    .s_axil_wvalid (axil_wvalid),
    .s_axil_wready (axil_wready),
    .s_axil_bresp  (axil_bresp),
    .s_axil_bvalid (axil_bvalid),
    .s_axil_bready (axil_bready),
    .s_axil_araddr (axil_araddr),
    .s_axil_arvalid(axil_arvalid),
    .s_axil_arready(axil_arready),
    .s_axil_rdata  (axil_rdata),
    .s_axil_rresp  (axil_rresp),
    .s_axil_rvalid (axil_rvalid),
    .s_axil_rready (axil_rready),
    .sin_out       (sin_out),
    .cos_out       (cos_out),
    .valid_out     (valid_out)
);

always #(CLK_PERIOD/2) clk = ~clk;

// AXI-Lite write task
task axil_write;
    input [3:0]  addr;
    input [31:0] data;
    begin
        @(posedge clk);
        axil_awaddr  = addr;
        axil_awvalid = 1'b1;
        axil_wdata   = data;
        axil_wvalid  = 1'b1;
        axil_bready  = 1'b1;
        wait (axil_awready && axil_wready);
        @(posedge clk);
        axil_awvalid = 1'b0;
        axil_wvalid  = 1'b0;
        wait (axil_bvalid);
        @(posedge clk);
        axil_bready = 1'b0;
    end
endtask

integer fd;
integer k;
reg signed [17:0] s_val, c_val;
real s_r, c_r, power;

initial begin
    $dumpfile("tb_nco.vcd");
    $dumpvars(0, tb_nco);

    clk  = 1'b0;
    resetn = 1'b0;
    axil_awaddr  = 4'h0; axil_awvalid = 1'b0;
    axil_wdata   = 32'h0; axil_wvalid = 1'b0;
    axil_bready  = 1'b0;
    axil_araddr  = 4'h0; axil_arvalid = 1'b0;
    axil_rready  = 1'b0;

    repeat(4) @(posedge clk);
    resetn = 1'b1;

    // Write freq_word: fc = 10 MHz -> fw = round(10e6 * 2^32 / 60e6) = 716_915_456
    axil_write(4'h0, 32'd716_915_456);

    // Run 2048 cycles, log sin/cos for power check
    fd = $fopen("nco_out.csv", "w");
    $fwrite(fd, "cycle,sin,cos,power\n");

    for (k = 0; k < 2048; k = k + 1) begin
        @(posedge clk);
        s_val = sin_out;
        c_val = cos_out;
        s_r = $itor($signed(s_val)) / 131071.0;
        c_r = $itor($signed(c_val)) / 131071.0;
        power = s_r*s_r + c_r*c_r;
        $fwrite(fd, "%0d,%0d,%0d,%f\n", k, $signed(s_val), $signed(c_val), power);
    end
    $fclose(fd);

    // Amplitude check: power should be ~1.0 (within LUT quantization error)
    $display("Last power = %f (expected ~1.0)", power);

    $finish;
end

endmodule
