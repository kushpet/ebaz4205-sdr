// hardware/rtl/cic_decimator.v
// CIC Decimator: N integrators @ fs, downsample ÷R, N comb @ fs/R
// Input: signed B_in bits (from complex_mixer: 13-bit I or Q)
// Internal width: B_in + N*LOG2_RMAX bits (no multipliers)
// Output: 16-bit signed with rounding
// Control: decimation_r via direct port (runtime-configurable from ddc_top)

module cic_decimator #(
    parameter N         = 5,
    parameter B_IN      = 13,
    parameter LOG2_RMAX = 7,                         // ceil(log2(120))=7
    parameter B_INT     = B_IN + N * LOG2_RMAX,      // 48
    parameter B_OUT     = 16
)(
    input  wire                 clk,
    input  wire                 resetn,

    // Input @ fs (from complex_mixer)
    input  wire [B_IN-1:0]      din,
    input  wire                 din_valid,

    // Decimation rate: 15, 30, 60, or 120
    input  wire [6:0]           decimation_r,

    // Output @ fs/R
    output reg  [B_OUT-1:0]     dout,
    output reg                  dout_valid
);

// --- Integrators @ fs ---
reg signed [B_INT-1:0] integ [0:N-1];

integer k;
always @(posedge clk) begin
    if (!resetn) begin
        for (k = 0; k < N; k = k + 1)
            integ[k] <= {B_INT{1'b0}};
    end else if (din_valid) begin
        integ[0] <= integ[0] + {{(B_INT-B_IN){din[B_IN-1]}}, din};
        for (k = 1; k < N; k = k + 1)
            integ[k] <= integ[k] + integ[k-1];
    end
end

// --- Downsampler ÷R ---
reg [6:0]              dec_cnt;
reg signed [B_INT-1:0] ds_reg;
reg                    ds_valid;

always @(posedge clk) begin
    if (!resetn) begin
        dec_cnt  <= 7'd0;
        ds_valid <= 1'b0;
    end else if (din_valid) begin
        if (dec_cnt == decimation_r - 1) begin
            dec_cnt  <= 7'd0;
            ds_reg   <= integ[N-1];
            ds_valid <= 1'b1;
        end else begin
            dec_cnt  <= dec_cnt + 1'b1;
            ds_valid <= 1'b0;
        end
    end else
        ds_valid <= 1'b0;
end

// --- Comb sections @ fs/R ---
reg signed [B_INT-1:0] comb_in  [0:N-1];
reg signed [B_INT-1:0] comb_out [0:N-1];
reg                    comb_valid [0:N-1];

integer j;
always @(posedge clk) begin
    if (!resetn) begin
        for (j = 0; j < N; j = j + 1) begin
            comb_in[j]    <= {B_INT{1'b0}};
            comb_out[j]   <= {B_INT{1'b0}};
            comb_valid[j] <= 1'b0;
        end
    end else begin
        if (ds_valid) begin
            comb_out[0]   <= ds_reg - comb_in[0];
            comb_in[0]    <= ds_reg;
            comb_valid[0] <= 1'b1;
        end else
            comb_valid[0] <= 1'b0;
        for (j = 1; j < N; j = j + 1) begin
            if (comb_valid[j-1]) begin
                comb_out[j]   <= comb_out[j-1] - comb_in[j];
                comb_in[j]    <= comb_out[j-1];
                comb_valid[j] <= 1'b1;
            end else
                comb_valid[j] <= 1'b0;
        end
    end
end

// --- Output: R-aware slice, then saturate to B_OUT ---
// CIC gain at runtime is R^N. The static slice [B_INT-1:B_INT-B_OUT]
// is only properly scaled at R = R_MAX (worst-case bit growth was the
// reason B_INT = B_IN + N*LOG2_RMAX). At lower R the slice drops the
// MSBs that actually carry the signal — R=30 loses ~11 bits (~66 dB
// in dout). Make the slice R-aware so dout swings into roughly the
// int16 range regardless of decimation. Filter transients can briefly
// overshoot the nominal range, so saturate rather than wrap.
reg [5:0] cic_shift;
always @(*) begin
    case (decimation_r)
        7'd15:   cic_shift = 6'd17;   // gain ≈ 2^19.5
        7'd30:   cic_shift = 6'd22;   // gain ≈ 2^24.5
        7'd60:   cic_shift = 6'd27;   // gain ≈ 2^29.5
        default: cic_shift = 6'd32;   // R=120: gain ≈ 2^34.5
    endcase
end

wire signed [B_INT-1:0] cic_out = comb_out[N-1];
wire signed [B_INT-1:0] shifted = cic_out >>> cic_shift;
wire signed [B_OUT-1:0] sat_pos = {1'b0, {(B_OUT-1){1'b1}}};   // +32767
wire signed [B_OUT-1:0] sat_neg = {1'b1, {(B_OUT-1){1'b0}}};   // -32768
wire signed [B_OUT-1:0] dout_w  =
    (shifted > sat_pos) ? sat_pos :
    (shifted < sat_neg) ? sat_neg :
                          shifted[B_OUT-1:0];

always @(posedge clk) begin
    if (!resetn) begin
        dout       <= {B_OUT{1'b0}};
        dout_valid <= 1'b0;
    end else if (comb_valid[N-1]) begin
        dout       <= dout_w;
        dout_valid <= 1'b1;
    end else
        dout_valid <= 1'b0;
end

endmodule
