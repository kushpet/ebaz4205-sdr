`timescale 1ns/1ps

module tb_dac_if;

// Parameters
localparam CLK_PERIOD = 16; // 62.5 MHz ~ 60 MHz

// DUT signals
reg         aclk = 0;
reg         aresetn = 0;
// AXI-Stream
reg  [15:0] tdata = 0;
reg         tvalid = 0;
wire        tready;
// AXI-Lite
reg  [3:0]  awaddr = 0;
reg         awvalid = 0;
wire        awready;
reg  [31:0] wdata = 0;
reg         wvalid = 0;
wire        wready;
wire [1:0]  bresp;
wire        bvalid;
reg         bready = 1;
reg  [3:0]  araddr = 0;
reg         arvalid = 0;
wire        arready;
wire [31:0] rdata;
wire [1:0]  rresp;
wire        rvalid;
reg         rready = 1;
// DAC pins
wire [13:0] DAC;
wire        CLK_DAC;
wire        PD;

dac_if dut (
    .s_axis_aclk    (aclk),
    .s_axis_aresetn (aresetn),
    .s_axis_tdata   (tdata),
    .s_axis_tvalid  (tvalid),
    .s_axis_tready  (tready),
    .s_axil_awaddr  (awaddr),
    .s_axil_awvalid (awvalid),
    .s_axil_awready (awready),
    .s_axil_wdata   (wdata),
    .s_axil_wvalid  (wvalid),
    .s_axil_wready  (wready),
    .s_axil_bresp   (bresp),
    .s_axil_bvalid  (bvalid),
    .s_axil_bready  (bready),
    .s_axil_araddr  (araddr),
    .s_axil_arvalid (arvalid),
    .s_axil_arready (arready),
    .s_axil_rdata   (rdata),
    .s_axil_rresp   (rresp),
    .s_axil_rvalid  (rvalid),
    .s_axil_rready  (rready),
    .DAC            (DAC),
    .CLK_DAC        (CLK_DAC),
    .PD             (PD)
);

always #(CLK_PERIOD/2) aclk = ~aclk;

task axil_write(input [3:0] addr, input [31:0] data);
    begin
        @(posedge aclk);
        awaddr  <= addr;
        awvalid <= 1;
        wdata   <= data;
        wvalid  <= 1;
        @(posedge aclk);
        wait(awready && wready);
        @(posedge aclk);
        awvalid <= 0;
        wvalid  <= 0;
        wait(bvalid);
        @(posedge aclk);
    end
endtask

task axil_read(input [3:0] addr);
    begin
        @(posedge aclk);
        araddr  <= addr;
        arvalid <= 1;
        wait(arready);
        @(posedge aclk);
        arvalid <= 0;
        wait(rvalid);
        @(posedge aclk);
    end
endtask

task axis_send(input [15:0] data);
    begin
        @(posedge aclk);
        tdata  <= data;
        tvalid <= 1;
        @(posedge aclk);
        tvalid <= 0;
    end
endtask

integer i;
initial begin
    $dumpfile("tb_dac_if.vcd");
    $dumpvars(0, tb_dac_if);

    // Reset
    repeat(4) @(posedge aclk);
    aresetn <= 1;
    repeat(2) @(posedge aclk);

    // Test 1: AXI-Stream data, check DAC[13:0] = tdata[13:0]
    axis_send(16'h3FFF); // all 14 bits set
    @(posedge aclk);
    if (DAC !== 14'h3FFF)
        $display("FAIL T1: DAC=0x%h expected 0x3FFF", DAC);
    else
        $display("PASS T1: DAC=0x%h", DAC);

    axis_send(16'hC000); // bits[15:14] set, [13:0]=0 -> DAC=0
    @(posedge aclk);
    if (DAC !== 14'h0000)
        $display("FAIL T2: DAC=0x%h expected 0x0000", DAC);
    else
        $display("PASS T2: DAC=0x%h (upper bits masked)", DAC);

    axis_send(16'h1234);
    @(posedge aclk);
    if (DAC !== 14'h1234)
        $display("FAIL T3: DAC=0x%h expected 0x1234", DAC);
    else
        $display("PASS T3: DAC=0x%h", DAC);

    // Test 2: AXI-Lite write PD=1
    axil_write(4'h0, 32'h1);
    @(posedge aclk);
    if (PD !== 1'b1)
        $display("FAIL T4: PD=%b expected 1", PD);
    else
        $display("PASS T4: PD=1 (power-down active)");

    // Test 3: AXI-Lite read back
    axil_read(4'h0);
    @(posedge aclk);
    if (rdata !== 32'h1)
        $display("FAIL T5: rdata=0x%h expected 0x1", rdata);
    else
        $display("PASS T5: readback=0x%h", rdata);

    // Test 4: PD=0 (normal operation)
    axil_write(4'h0, 32'h0);
    @(posedge aclk);
    if (PD !== 1'b0)
        $display("FAIL T6: PD=%b expected 0", PD);
    else
        $display("PASS T6: PD=0 (normal operation)");

    // Test 5: stream of samples
    for (i = 0; i < 8; i = i+1)
        axis_send(i * 16'h0200);

    repeat(4) @(posedge aclk);
    $display("DONE");
    $finish;
end

// Timeout
initial begin
    #100000;
    $display("TIMEOUT");
    $finish;
end

endmodule
