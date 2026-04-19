// hardware/rtl/hb_fir_interpolator.v
// Halfband FIR interpolator x2, 63-tap (32 non-zero), transposed form
// CIC-compensating coefficients (R_max=120, N=5, Parks-McClellan)
// Input: 16-bit signed @ fs_cic/2  Output: 16-bit signed @ fs_cic
// Single channel — instantiate for I and Q separately
// DSP48: 16 (symmetric pairs, center = >>1 shift)
//
// Transposed interpolation: zero-insert x2, then filter
// Equivalent: two polyphase branches (even/odd samples)

module hb_fir_interpolator #(
    parameter B_IN  = 16,
    parameter B_OUT = 16,
    parameter B_ACC = 42,
    parameter AXI_ADDR_WIDTH = 6
)(
    input  wire               clk,
    input  wire               resetn,
    input  wire [B_IN-1:0]    din,
    input  wire               din_valid,   // @ fs_cic/2 (one pulse per 2 output clocks)
    output reg  [B_OUT-1:0]   dout,
    output reg                dout_valid,  // @ fs_cic (every clock when active)
    // AXI-Lite: optional coefficient reload
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

// ---- Coefficients (same as decimator) ----
reg signed [17:0] coef [0:15];
integer ci;
initial begin
    coef[ 0] = 18'sh3FFB2; // h[ 0] =    -78
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

// ---- AXI-Lite ----
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

// ---- Polyphase decomposition of halfband interpolator ----
// HB interpolator x2: odd polyphase = delta (pass-through at Fs/2 rate)
//                     even polyphase = 31-tap lowpass * 2
// At output rate (fs_cic):
//   even output samples: apply filter (16 DSP + center>>1)
//   odd  output samples: din delayed by (N-1)/2 = 31 cycles @ Fs/2 rate
//
// Implementation: 
//   phase=0: compute filter output (MAC on 63-tap delay line @ Fs/2)
//   phase=1: pass center tap (delayed input), scaled by 2 (gain=1 after /2)

// Shift register at Fs/2 rate (input rate)
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

// Output phase counter at Fs_cic rate
reg out_phase;
reg din_valid_d;
always @(posedge clk) begin
    if (!resetn) begin
        out_phase <= 1'b0; din_valid_d <= 1'b0;
    end else begin
        din_valid_d <= din_valid;
        if (din_valid) out_phase <= 1'b0;
        else if (din_valid_d) out_phase <= 1'b1;
    end
end

// Symmetric pre-adds (computed when din_valid, for filter branch)
wire signed [B_IN:0] sym_add [0:15];
genvar k;
generate
    for (k = 0; k < 16; k = k + 1) begin : GEN_SYM
        assign sym_add[k] = {{1{sr[2*k][B_IN-1]}}, sr[2*k]} +
                            {{1{sr[62-2*k][B_IN-1]}}, sr[62-2*k]};
    end
endgenerate

// Pipeline: multiply (registered when din_valid)
reg signed [B_IN+18:0] prod [0:15];
reg pipe1_fir;
always @(posedge clk) begin
    if (!resetn) begin
        pipe1_fir <= 1'b0;
        for (i = 0; i < 16; i = i + 1) prod[i] <= {(B_IN+19){1'b0}};
    end else begin
        pipe1_fir <= din_valid;
        if (din_valid)
            for (i = 0; i < 16; i = i + 1)
                prod[i] <= sym_add[i] * coef[i];
    end
end

// Pipeline: accumulate FIR
reg signed [B_ACC-1:0] acc_fir;
reg pipe2_fir;
wire signed [B_IN-1:0] center_tap = sr[31];
wire signed [B_IN:0]   center_half = {center_tap[B_IN-1], center_tap[B_IN-1:1]};

always @(posedge clk) begin
    if (!resetn) begin
        acc_fir <= {B_ACC{1'b0}}; pipe2_fir <= 1'b0;
    end else begin
        pipe2_fir <= pipe1_fir;
        if (pipe1_fir)
            acc_fir <= {{(B_ACC-B_IN-1){center_half[B_IN]}}, center_half} +
                       prod[ 0] + prod[ 1] + prod[ 2] + prod[ 3] +
                       prod[ 4] + prod[ 5] + prod[ 6] + prod[ 7] +
                       prod[ 8] + prod[ 9] + prod[10] + prod[11] +
                       prod[12] + prod[13] + prod[14] + prod[15];
    end
end

// Pass-through branch (odd output): sr[31] is center @ Fs/2, no scaling
// For gain=1: odd output = sr[31] (HB passthrough polyphase = delta)
// Pipeline to match FIR latency (2 cycles)
reg signed [B_IN-1:0] pass_d1, pass_d2;
always @(posedge clk) begin
    if (!resetn) begin
        pass_d1 <= {B_IN{1'b0}}; pass_d2 <= {B_IN{1'b0}};
    end else if (din_valid) begin
        pass_d1 <= sr[31];
        pass_d2 <= pass_d1;
    end
end

// Output mux: phase=0 -> FIR result (even), phase=1 -> pass (odd)
localparam SHIFT = 16;
wire signed [B_ACC-1:0] rounded_fir = acc_fir + {{(B_ACC-1){1'b0}}, acc_fir[SHIFT-1]};

always @(posedge clk) begin
    if (!resetn) begin
        dout <= {B_OUT{1'b0}}; dout_valid <= 1'b0;
    end else begin
        if (pipe2_fir) begin
            // Even output: FIR branch (×2 gain correction via coef scaling already)
            dout_valid <= 1'b1;
            dout <= rounded_fir[B_OUT+SHIFT-1:SHIFT];
        end else if (din_valid_d && !pipe2_fir) begin
            // Odd output: pass-through branch
            dout_valid <= 1'b1;
            dout <= pass_d2;
        end else
            dout_valid <= 1'b0;
    end
end

endmodule
