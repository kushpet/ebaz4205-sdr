// hardware/rtl/complex_mixer.v
// DDC mode (duc_mode=0): I = data_in * cos, Q = data_in * sin
// DUC mode (duc_mode=1): out = I_in * cos - Q_in * sin  (real output)
//
// DDC path (from p.1.4 adc_if.v):
//   data_in[11:0]  <- adc_if.m_axis_tdata[11:0] (signed 12-bit, twos complement)
//   sin/cos[17:0]  <- nco.sin_out / nco.cos_out  (signed 18-bit, scale 2^17-1)
//
// Multiplier: 12-bit * 18-bit = 30-bit product, truncate to 13-bit (drop bottom 17 bits)
// DSP48E1: A=30b, B=18b — use A[17:0]=sin/cos, B[11:0]=data_in (zero-extend to 18b)
//   actual mapping: P[29:0] = A[17:0] * B[17:0], keep P[29:17] -> 13 bits
//
// DUC path:
//   I_in[12:0], Q_in[12:0] -> I*cos - Q*sin -> duc_out[13:0] (14-bit for DAC904)

module complex_mixer (
    input  wire        clk,
    input  wire        resetn,
    input  wire        duc_mode,    // 0=DDC, 1=DUC

    // DDC inputs
    input  wire [11:0] data_in,     // from adc_if, signed 12-bit

    // DUC inputs
    input  wire [12:0] I_in,        // signed 13-bit
    input  wire [12:0] Q_in,        // signed 13-bit

    // NCO inputs (from nco.v, 1-cycle delayed from phase_acc)
    input  wire [17:0] sin_in,      // signed 18-bit
    input  wire [17:0] cos_in,      // signed 18-bit
    input  wire        nco_valid,

    // DDC outputs: I = Re, Q = Im
    output reg  [12:0] I_out,       // signed 13-bit
    output reg  [12:0] Q_out,       // signed 13-bit

    // DUC output: real signal to DAC (14-bit to fill DAC904 range)
    output reg  [13:0] duc_out,     // signed 14-bit

    output reg         valid_out
);

// Pipeline stage 1: sign-extend data_in to 18-bit for DSP
wire signed [17:0] data_se = {{6{data_in[11]}}, data_in};

// DSP48E1 inference: two multipliers
// Mult A: data_se * cos_in -> I (DDC) or I_in * cos_in (DUC)
// Mult B: data_se * sin_in -> Q (DDC) or Q_in * sin_in (DUC)

wire signed [17:0] mux_a = duc_mode ? {{5{I_in[12]}}, I_in} : data_se;
wire signed [17:0] mux_b = duc_mode ? {{5{Q_in[12]}}, Q_in} : data_se;

// DSP48 inferred as: (* use_dsp = "yes" *)
(* use_dsp = "yes" *) wire signed [35:0] prod_I = mux_a * $signed(cos_in);
(* use_dsp = "yes" *) wire signed [35:0] prod_Q = mux_b * $signed(sin_in);

// Truncate: 18-bit * 18-bit = 36-bit; scale = 2^17-1 -> keep [35:17] = 19 bits,
// then take [30:18] -> 13 bits (drop bottom 17, keep next 13 for SNR)
// I_out = prod_I[30:18], Q_out = prod_Q[30:18]

// DUC: I*cos - Q*sin, 36-bit subtract, keep [31:18] -> 14-bit
wire signed [35:0] duc_sum = prod_I - prod_Q;

always @(posedge clk) begin
    if (!resetn) begin
        I_out    <= 13'd0;
        Q_out    <= 13'd0;
        duc_out  <= 14'd0;
        valid_out <= 1'b0;
    end else if (nco_valid) begin
        I_out    <= prod_I[30:18];
        Q_out    <= prod_Q[30:18];
        duc_out  <= duc_sum[31:18];
        valid_out <= 1'b1;
    end else begin
        valid_out <= 1'b0;
    end
end

endmodule
