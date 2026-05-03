# Step 4 — Q-sign mirror fix in `complex_mixer.v`

You're picking up `ebaz4205-sdr` (see `CLAUDE.md`). The DDC produces a
frequency-mirrored baseband because `complex_mixer.v` computes
`Q = data·sin` instead of `Q = −data·sin`. SDRAngel can flip via
"swap I/Q", but we should fix it properly.

## Read first

1. `CLAUDE.md` (note it explicitly under "Known caveats")
2. `hardware/rtl/complex_mixer.v` — single-line fix

## What to do

Locate the Q output in `complex_mixer.v` (DDC mode, where `duc_mode=0`)
and negate it. The mixer DSP path is:

- `prod_I = data · cos`  → kept positive (correct)
- `prod_Q = data · sin`  → should be negated for proper analytic signal

Easiest place: where `Q_out` is assigned, take the two's-complement
of the multiplier output (or flip a sign bit on `mux_b`).

Don't touch DUC mode (`duc_mode=1`) — its math is already correct
(`I·cos − Q·sin`).

## Build & verify

Full FPGA rebuild — see `docs/prompts/01-ddc-tlast.md` § "Build chain"
(steps 1 + 3; firmware unchanged).

Hardware check: with a known carrier on the ADC, SDRAngel should
display it at the correct (non-mirrored) side of DC. If you previously
had to enable "swap I/Q" in SDRAngel, you can disable it now.

When done: short commit (`"complex_mixer: negate Q for proper analytic signal"`),
remove the caveat from `CLAUDE.md`, mark row 4 ✅ in `docs/NEXT_STEPS.md`.
