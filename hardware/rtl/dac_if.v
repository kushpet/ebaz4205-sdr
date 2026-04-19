// DAC904 interface: parallel 14-bit output, AXI-Stream input, AXI-Lite PD control
// CLK_DAC: A20, PD: J18, DAC[0..13]: see XDC
// Data latched on rising edge of CLK_DAC (DAC904 datasheet)
// Board mapping: BIT1=D13(MSB)..BIT14=D0(LSB), connector JP1 pins 5..18
// FPGA DAC[0](G20) -> BIT14 -> D0(LSB), DAC[13](H16) -> BIT1 -> D13(MSB)

module dac_if #(
    parameter AXI_ADDR_WIDTH = 4
)(
    // AXI-Stream slave
    input  wire        s_axis_aclk,
    input  wire        s_axis_aresetn,
    input  wire [15:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    // AXI-Lite slave (single reg: offset 0 -> bit0 = PD)
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output reg         s_axil_awready,
    input  wire [31:0] s_axil_wdata,
    input  wire        s_axil_wvalid,
    output reg         s_axil_wready,
    output reg  [1:0]  s_axil_bresp,
    output reg         s_axil_bvalid,
    input  wire        s_axil_bready,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_araddr,
    input  wire        s_axil_arvalid,
    output reg         s_axil_arready,
    output reg  [31:0] s_axil_rdata,
    output reg  [1:0]  s_axil_rresp,
    output reg         s_axil_rvalid,
    input  wire        s_axil_rready,

    // DAC904 physical pins
    output reg  [13:0] DAC,
    output wire        CLK_DAC,
    output reg         PD
);

// CLK_DAC driven directly from AXI-Stream clock (60 MHz)
assign CLK_DAC = s_axis_aclk;

// AXI-Stream: always ready, latch data on valid
assign s_axis_tready = 1'b1;

always @(posedge s_axis_aclk) begin
    if (!s_axis_aresetn) begin
        DAC <= 14'd0;
    end else if (s_axis_tvalid) begin
        // bits[13:0] of TDATA -> DAC[13:0]
        // DAC[0]=MSB(D13), DAC[13]=LSB(D0) per board schematic JP1 mapping
        DAC <= s_axis_tdata[13:0];
    end
end

// AXI-Lite: write channel
reg  [31:0] reg_ctrl; // bit0 = PD

always @(posedge s_axis_aclk) begin
    if (!s_axis_aresetn) begin
        reg_ctrl      <= 32'd0;
        s_axil_awready <= 1'b0;
        s_axil_wready  <= 1'b0;
        s_axil_bvalid  <= 1'b0;
        s_axil_bresp   <= 2'b00;
    end else begin
        s_axil_awready <= s_axil_awvalid & s_axil_wvalid & ~s_axil_awready;
        s_axil_wready  <= s_axil_awvalid & s_axil_wvalid & ~s_axil_wready;
        if (s_axil_awvalid && s_axil_wvalid && s_axil_awready && s_axil_wready) begin
            reg_ctrl      <= s_axil_wdata;
            s_axil_bvalid <= 1'b1;
            s_axil_bresp  <= 2'b00;
        end else if (s_axil_bready) begin
            s_axil_bvalid <= 1'b0;
        end
    end
end

// AXI-Lite: read channel
always @(posedge s_axis_aclk) begin
    if (!s_axis_aresetn) begin
        s_axil_arready <= 1'b0;
        s_axil_rvalid  <= 1'b0;
        s_axil_rdata   <= 32'd0;
        s_axil_rresp   <= 2'b00;
    end else begin
        if (s_axil_arvalid && ~s_axil_arready) begin
            s_axil_arready <= 1'b1;
            s_axil_rdata   <= reg_ctrl;
            s_axil_rresp   <= 2'b00;
            s_axil_rvalid  <= 1'b1;
        end else begin
            s_axil_arready <= 1'b0;
        end
        if (s_axil_rvalid && s_axil_rready)
            s_axil_rvalid <= 1'b0;
    end
end

// PD output from register bit0
always @(posedge s_axis_aclk) begin
    if (!s_axis_aresetn)
        PD <= 1'b0;
    else
        PD <= reg_ctrl[0];
end

endmodule
