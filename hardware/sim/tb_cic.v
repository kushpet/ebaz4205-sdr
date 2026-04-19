// hardware/sim/tb_cic.v
// Testbench: cic_decimator + cic_interpolator back-to-back
// Stimulus: sine wave at fin = fs/32, verify decimated output freq = fin*R/fs

`timescale 1ns/1ps

module tb_cic;

localparam N         = 5;
localparam B_IN      = 13;
localparam LOG2_RMAX = 7;
localparam B_INT_DEC = B_IN + N * LOG2_RMAX;   // 48
localparam B_IN_INT  = 16;
localparam B_INT_INT = B_IN_INT + N * LOG2_RMAX; // 51
localparam B_OUT     = 16;
localparam R_TEST    = 7'd30;
localparam CLK_PERIOD = 16.667; // 60 MHz

reg clk, resetn;
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// --- Sine stimulus (13-bit, ~fs/32) ---
reg  [12:0] din;
reg         din_valid;
integer     phase_cnt;
real        pi = 3.14159265358979;

initial phase_cnt = 0;
always @(posedge clk) begin
    if (!resetn) begin
        phase_cnt <= 0;
        din       <= 13'd0;
        din_valid <= 1'b0;
    end else begin
        din       <= $rtoi($sin(2.0 * pi * phase_cnt / 32.0) * 4000.0);
        din_valid <= 1'b1;
        phase_cnt <= phase_cnt + 1;
    end
end

// --- DUT: cic_decimator ---
wire [B_OUT-1:0] dec_out;
wire             dec_valid;

// Tie off unused AXI-Lite (write path, use reset defaults R=30)
cic_decimator #(.N(N), .B_IN(B_IN), .LOG2_RMAX(LOG2_RMAX), .B_OUT(B_OUT)) u_dec (
    .clk(clk), .resetn(resetn),
    .din(din), .din_valid(din_valid),
    .dout(dec_out), .dout_valid(dec_valid),
    .s_axil_awaddr(4'd0), .s_axil_awvalid(1'b0),
    .s_axil_awready(),
    .s_axil_wdata(32'd0), .s_axil_wvalid(1'b0),
    .s_axil_wready(),
    .s_axil_bresp(), .s_axil_bvalid(), .s_axil_bready(1'b1),
    .s_axil_araddr(4'd0), .s_axil_arvalid(1'b0),
    .s_axil_arready(),
    .s_axil_rdata(), .s_axil_rresp(), .s_axil_rvalid(),
    .s_axil_rready(1'b1)
);

// --- DUT: cic_interpolator ---
wire [B_OUT-1:0] int_out;
wire             int_valid;

cic_interpolator #(.N(N), .B_IN(B_IN_INT), .LOG2_RMAX(LOG2_RMAX), .B_OUT(B_OUT)) u_int (
    .clk(clk), .resetn(resetn),
    .din(dec_out), .din_valid(dec_valid),
    .dout(int_out), .dout_valid(int_valid),
    .s_axil_awaddr(4'd0), .s_axil_awvalid(1'b0),
    .s_axil_awready(),
    .s_axil_wdata(32'd0), .s_axil_wvalid(1'b0),
    .s_axil_wready(),
    .s_axil_bresp(), .s_axil_bvalid(), .s_axil_bready(1'b1),
    .s_axil_araddr(4'd0), .s_axil_arvalid(1'b0),
    .s_axil_arready(),
    .s_axil_rdata(), .s_axil_rresp(), .s_axil_rvalid(),
    .s_axil_rready(1'b1)
);

// --- Log output ---
integer fout;
initial fout = $fopen("tb_cic_out.txt", "w");

always @(posedge clk)
    if (dec_valid)
        $fwrite(fout, "DEC %0d\n", $signed(dec_out));

always @(posedge clk)
    if (int_valid)
        $fwrite(fout, "INT %0d\n", $signed(int_out));

// --- Simulation control ---
initial begin
    resetn = 0;
    #(CLK_PERIOD * 10);
    resetn = 1;
    #(CLK_PERIOD * 8000);
    $fclose(fout);
    $finish;
end

// Timeout
initial begin
    #(CLK_PERIOD * 100000);
    $display("TIMEOUT");
    $finish;
end

endmodule


