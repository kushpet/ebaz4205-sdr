// hardware/rtl/nco.v
// NCO: 32-bit phase accumulator + 1024x18 sin/cos LUT (BRAM)
// AXI-Lite slave @ base addr: offset 0x00 = freq_word[31:0]
// Outputs: sin_out[17:0], cos_out[17:0] @ 60 MHz (clk_60mhz from p.1.3)
// LUT values: signed 18-bit, full-scale = 2^17-1 = 131071
// Phase: top 10 bits -> LUT address (1024 entries)
// 1 BRAM18 (true dual-port): port A = cos, port B = sin

module nco #(
    parameter AXI_ADDR_WIDTH = 4
)(
    input  wire        clk,        // 60 MHz
    input  wire        resetn,

    // AXI-Lite slave
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

    output reg  [17:0] sin_out,
    output reg  [17:0] cos_out,
    output reg         valid_out
);

// --- Phase accumulator ---
reg [31:0] freq_word;
reg [31:0] phase_acc;

always @(posedge clk) begin
    if (!resetn)
        phase_acc <= 32'd0;
    else
        phase_acc <= phase_acc + freq_word;
end

// Top 10 bits = LUT address
wire [9:0] lut_addr = phase_acc[31:22];

// --- sin/cos LUT (1024 x 18-bit, BRAM inference) ---
// Initialized via $readmemh; generate sincos_lut.hex at synthesis
(* rom_style = "block" *)
reg [35:0] sincos_lut [0:1023]; // [35:18]=cos, [17:0]=sin

integer i;
initial begin
    for (i = 0; i < 1024; i = i + 1) begin
        // cos in [35:18], sin in [17:0]; signed 18-bit, scale 2^17-1
        sincos_lut[i][17:0]  = $signed($rtoi($sin(2.0*3.14159265358979323846*i/1024.0) * 131071.0));
        sincos_lut[i][35:18] = $signed($rtoi($cos(2.0*3.14159265358979323846*i/1024.0) * 131071.0));
    end
end

// 1-cycle pipeline: address register -> LUT read
reg [9:0] lut_addr_r;
always @(posedge clk) begin
    if (!resetn) begin
        lut_addr_r <= 10'd0;
        sin_out    <= 18'd0;
        cos_out    <= 18'd0;
        valid_out  <= 1'b0;
    end else begin
        lut_addr_r <= lut_addr;
        sin_out    <= sincos_lut[lut_addr_r][17:0];
        cos_out    <= sincos_lut[lut_addr_r][35:18];
        valid_out  <= 1'b1;
    end
end

// --- AXI-Lite: write (offset 0x00 = freq_word) ---
always @(posedge clk) begin
    if (!resetn) begin
        freq_word      <= 32'd0;
        s_axil_awready <= 1'b0;
        s_axil_wready  <= 1'b0;
        s_axil_bvalid  <= 1'b0;
        s_axil_bresp   <= 2'b00;
    end else begin
        s_axil_awready <= s_axil_awvalid & s_axil_wvalid & ~s_axil_awready;
        s_axil_wready  <= s_axil_awvalid & s_axil_wvalid & ~s_axil_wready;
        if (s_axil_awvalid && s_axil_wvalid && s_axil_awready && s_axil_wready) begin
            if (s_axil_awaddr[3:2] == 2'b00)
                freq_word     <= s_axil_wdata;
            s_axil_bvalid <= 1'b1;
            s_axil_bresp  <= 2'b00;
        end else if (s_axil_bready) begin
            s_axil_bvalid <= 1'b0;
        end
    end
end

// --- AXI-Lite: read ---
always @(posedge clk) begin
    if (!resetn) begin
        s_axil_arready <= 1'b0;
        s_axil_rvalid  <= 1'b0;
        s_axil_rdata   <= 32'd0;
        s_axil_rresp   <= 2'b00;
    end else begin
        if (s_axil_arvalid && ~s_axil_arready) begin
            s_axil_arready <= 1'b1;
            s_axil_rdata   <= freq_word;
            s_axil_rresp   <= 2'b00;
            s_axil_rvalid  <= 1'b1;
        end else begin
            s_axil_arready <= 1'b0;
        end
        if (s_axil_rvalid && s_axil_rready)
            s_axil_rvalid <= 1'b0;
    end
end

endmodule
