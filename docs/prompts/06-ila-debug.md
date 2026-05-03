# Step 6 — ILA debug instrumentation (Phase 3.2)

You're picking up `ebaz4205-sdr` (see `CLAUDE.md`). The original plan
called for ILA cores in the Block Design at three observation points;
they were deferred for the first hardware bring-up.

## Read first

1. `CLAUDE.md`
2. `docs/PROGRESS.md` row 3.2
3. `hardware/scripts/create_bd.tcl` — the file you'll extend

## What to do

Add `xilinx.com:ip:ila:6.2` instances at three observation points,
hooked off the existing nets:

1. **AXI-Stream from `adc_if`** (post-ADC, pre-mixer): TDATA, TVALID,
   TREADY, OTR. 1024-deep, trigger on OTR rising edge. Useful for
   diagnosing ADC overflow.
2. **AXI-Stream into `dma0/S_AXIS_S2MM`** (post-DDC, post-clock-converter):
   TDATA[31:0] (Q hi / I lo), TVALID, TREADY, TLAST. 1024-deep. Useful
   for diagnosing the TLAST issue from step 1 if it's still noisy.
3. **AXI-Stream out of `dma1/M_AXIS_MM2S`** (pre-DUC): mirror of (2)
   for the TX path.

Use `connect_bd_net` taps (don't break existing connections — ILA
just sniffs the nets).

After the BD is regenerated, re-run synth+impl. Bitstream gets a
debug-hub — Vivado Hardware Manager will pick up the ILA cores when
you connect via JTAG.

## Build & verify

```bash
source /home/user/Xilinx/Vivado/2022.2/settings64.sh
cd hardware/scripts
rm -rf ../ebaz4205_sdr_vivado
vivado -mode batch -nojournal -nolog -source create_project.tcl
vivado -mode batch -nojournal -nolog -source run_bd.tcl
vivado -mode batch -nojournal -nolog -source run_synth_impl.tcl
vivado -mode batch -nojournal -nolog -source export_xsa.tcl
cd ../../firmware/sd_boot && bootgen -arch zynq -image boot.bif -o BOOT.bin -w on
```

Resource check: ILA cores cost BRAM and LUTs. Three 1024-deep ILAs
use ≈3 BRAM18 each. We had 5 % BRAM utilisation; budget allows it.

When done: hardware verification is "open Vivado Hardware Manager,
trigger an ILA, see waveforms". Document briefly in `docs/debug.md`
how to do it. Mark row 6 ✅ in `docs/NEXT_STEPS.md`.
