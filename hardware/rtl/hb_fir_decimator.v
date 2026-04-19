// hardware/rtl/hb_fir_decimator.v
// Halfband FIR decimator x2, 63-tap (32 non-zero), transposed form
// CIC-compensating coefficients (R_max=120, N=5, Parks-McClellan)
// Input: 16-bit signed @ fs_cic  Output: 16-bit signed @ fs_cic/2
// Single channel — instantiate for I and Q separately
// DSP48: 16 (symmetric pairs, center = >>1 shift, no DSP)
//
// Coefficient set (h[0],h[2],...,h[30]): 18-bit Q16
//   h[31]=65536 (center, 0.5 in Q16, done as arithmetic right shift)
//   h[i] = h[62-i] (linear phase symmetry)

module hb_fir_decimator #(
    parameter B_IN  = 16,
    parameter B_OUT = 16,
    parameter B_ACC = 42,   // B_IN+1 + 18 + log2(16) = 39 -> 42 safe
    parameter AXI_ADDR_WIDTH = 6
)(
    input  wire               clk,
    input  wire               resetn,
    input  wire [B_IN-1:0]    din,
    input  wire               din_valid,
    output reg  [B_OUT-1:0]   dout,
    output reg                dout_valid,
    // AXI-Lite: optional coefficient reload (offsets 0x00..0x3C = 16 regs)
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_awaddr,
    input  wire               s_axil_awvalid,
    output reg                s_axil_awready,
    input  wire [31:0]        s_axil_wdata,
    input  wire               s_axil_wvalid,
    output reg                s_axil_wready,
    output reg  [1:0]         s_axil_bresp,
    output reg                s_axil_bvalid,
    input  wire               s_axil_bready,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axil_araddr,
    input  wire               s_axil_arvalid,
    output reg                s_axil_arready,
    output reg  [31:0]        s_axil_rdata,
    output reg  [1:0]         s_axil_rresp,
    output reg                s_axil_rvalid,
    input  wire               s_axil_rready
);

// ---- Coefficients ROM (16 values, h[0],h[2],...,h[30]) ----
// Stored as 18-bit signed Q16 (1 sign + 1 integer + 16 frac)
// CIC-compensating for R_max=120, Parks-McClellan
reg signed [17:0] coef [0:15];
integer ci;
initial begin
    coef[ 0] = 18'sh3FFB2; // h[ 0] =    -78  (sign-extended 18-bit)
    coef[ 1] = 18'sh000C2; // h[ 2] =    194
    coef[ 2] = 18'sh3FF17; // h[ 4] =   -233
    coef[ 3] = 18'sh0016A; // h[ 6] =    362
    coef[ 4] = 18'sh3FDFE; // h[ 8] =   -514
    coef[ 5] = 18'sh002C9; // h[10] =    713
    coef[ 6] = 18'sh3FC3E; // h[12] =   -966
    coef[ 7] = 18'sh00507; // h[14] =   1287
    coef[ 8] = 18'sh3F961; // h[16] =  -1695
    coef[ 9] = 18'sh008AF; // h[18] =   2223
    coef[10] = 18'sh3F4DC; // h[20] =  -2924
    coef[11] = 18'sh00F3C; // h[22] =   3900
    coef[12] = 18'sh3EAD4; // h[24] =  -5372
    coef[13] = 18'sh01EEC; // h[26] =   7916
    coef[14] = 18'sh3CA71; // h[28] = -13647
    coef[15] = 18'sh0A2A2; // h[30] =  41634
end

// ---- AXI-Lite: coefficient reload ----
always @(posedge clk) begin
    if (!resetn) begin
        s_axil_awready <= 1'b0; s_axil_wready <= 1'b0;
        s_axil_bvalid  <= 1'b0; s_axil_bresp  <= 2'b00;
    end else begin
        s_axil_awready <= s_axil_awvalid & s_axil_wvalid & ~s_axil_awready;
        s_axil_wready  <= s_axil_awvalid & s_axil_wvalid & ~s_axil_wready;
        if (s_axil_awvalid && s_axil_wvalid && s_axil_awready && s_axil_wready) begin
            coef[s_axil_awaddr[5:2]] <= s_axil_wdata[17:0];
            s_axil_bvalid <= 1'b1; s_axil_bresp <= 2'b00;
        end else if (s_axil_bready)
            s_axil_bvalid <= 1'b0;
    end
end
always @(posedge clk) begin
    if (!resetn) begin
        s_axil_arready <= 1'b0; s_axil_rvalid <= 1'b0;
        s_axil_rdata   <= 32'd0; s_axil_rresp  <= 2'b00;
    end else begin
        if (s_axil_arvalid && ~s_axil_arready) begin
            s_axil_arready <= 1'b1;
            s_axil_rdata   <= {14'd0, coef[s_axil_araddr[5:2]]};
            s_axil_rresp   <= 2'b00; s_axil_rvalid <= 1'b1;
        end else
            s_axil_arready <= 1'b0;
        if (s_axil_rvalid && s_axil_rready)
            s_axil_rvalid <= 1'b0;
    end
end

// ---- Sample shift register: 63 taps ----
reg signed [B_IN-1:0] sr [0:62];
integer i;
always @(posedge clk) begin
    if (!resetn) begin
        for (i = 0; i < 63; i = i + 1) sr[i] <= {B_IN{1'b0}};
    end else if (din_valid) begin
        sr[0] <= din;
        for (i = 1; i < 63; i = i + 1) sr[i] <= sr[i-1];
    end
end

// ---- Decimation counter: output every 2nd input sample ----
reg phase;
always @(posedge clk) begin
    if (!resetn)       phase <= 1'b0;
    else if (din_valid) phase <= ~phase;
end

// ---- Transposed-form symmetric FIR ----
// On even phase (phase==0 after input):
// Pre-add: sym_add[k] = sr[2k] + sr[62-2k]  (k=0..15)
// Multiply: sym_add[k] * coef[k]
// Center:   sr[31] >> 1  (h[31]=0.5 exactly)
// Sum all -> accumulator

wire signed [B_IN:0] sym_add [0:15];
genvar k;
generate
    for (k = 0; k < 16; k = k + 1) begin : GEN_SYM
        assign sym_add[k] = {{1{sr[2*k][B_IN-1]}}, sr[2*k]} +
                            {{1{sr[62-2*k][B_IN-1]}}, sr[62-2*k]};
    end
endgenerate

// Pipeline stage 1: multiply sym_add[k] * coef[k]
reg signed [B_IN+18:0] prod [0:15];  // (B_IN+1) + 18 = 35 bits
reg                    pipe1_valid;
always @(posedge clk) begin
    if (!resetn) begin
        pipe1_valid <= 1'b0;
        for (i = 0; i < 16; i = i + 1) prod[i] <= {(B_IN+19){1'b0}};
    end else begin
        pipe1_valid <= din_valid && (phase == 1'b0);
        if (din_valid && (phase == 1'b0))
            for (i = 0; i < 16; i = i + 1)
                prod[i] <= sym_add[i] * coef[i];
    end
end

// Pipeline stage 2: tree sum of 16 products + center term
reg signed [B_ACC-1:0] acc;
reg                    pipe2_valid;

wire signed [B_IN-1:0] center_tap = sr[31];
wire signed [B_IN:0]   center_half = {center_tap[B_IN-1], center_tap[B_IN-1:1]};  // >>1 with sign

always @(posedge clk) begin
    if (!resetn) begin
        acc <= {B_ACC{1'b0}}; pipe2_valid <= 1'b0;
    end else begin
        pipe2_valid <= pipe1_valid;
        if (pipe1_valid) begin
            acc <= {{(B_ACC-B_IN-1){center_half[B_IN]}}, center_half} +
                   prod[ 0] + prod[ 1] + prod[ 2] + prod[ 3] +
                   prod[ 4] + prod[ 5] + prod[ 6] + prod[ 7] +
                   prod[ 8] + prod[ 9] + prod[10] + prod[11] +
                   prod[12] + prod[13] + prod[14] + prod[15];
        end
    end
end

// Output rounding: B_ACC -> B_OUT (truncate with round-to-nearest)
localparam SHIFT = 16;  // Q16 coefficient scale
wire signed [B_ACC-1:0] rounded = acc + {{(B_ACC-1){1'b0}}, acc[SHIFT-1]};
always @(posedge clk) begin
    if (!resetn) begin
        dout <= {B_OUT{1'b0}}; dout_valid <= 1'b0;
    end else begin
        dout_valid <= pipe2_valid;
        if (pipe2_valid)
            dout <= rounded[B_ACC-1:SHIFT] > $signed({1'b0,{(B_OUT-1){1'b1}}}) ?
                    {1'b0,{(B_OUT-1){1'b1}}} :
                    rounded[B_ACC-1:SHIFT] < $signed({1'b1,{(B_OUT-1){1'b0}}}) ?
                    {1'b1,{(B_OUT-1){1'b0}}} :
                    rounded[B_OUT+SHIFT-1:SHIFT];
    end
end

endmodule
