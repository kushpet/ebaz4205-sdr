# Step 1 — Add `m_axis_tlast` to ddc_top to clear `[rx_task] DMA timeout`

You're picking up `ebaz4205-sdr` — a Zynq-7010 SDR transceiver
(EBAZ4205 board) running bare-metal FreeRTOS + lwIP, controlled by
SDRAngel. Working directory:
`/home/user/GitHub/kushpet/ebaz4205-sdr`.

## Read first

1. `CLAUDE.md` — project overview, address map, EBAZ4205 board quirks,
   Xilinx lwIP-port quirks, build commands. **Required.**
2. `docs/REVIEW.md` — last iteration's verified status. The DDC TLAST
   item is what you're fixing.
3. `docs/NEXT_STEPS.md` — index of remaining work. When you're done,
   mark this row ✅.
4. `hardware/rtl/ddc_top.v` — the file you'll modify.

## Why DMA times out

The Xilinx AXI DMA in direct-register (non-SG) mode needs
`m_axis_tlast` asserted on the last beat of each buffer to know the
transfer is complete. `ddc_top.v` currently drives `m_axis_tdata` and
`m_axis_tvalid` only — the DMA stalls waiting for TLAST. This was a
critical *warning* during BD validation (not an error), so the
bitstream still built — but on hardware `[rx_task] DMA timeout` fires
every poll cycle.

## What to change

### 1. `hardware/rtl/ddc_top.v`

- Add a register `reg_samples_per_packet[31:0]` at AXI-Lite offset
  `0x0C`. Default `32'd4096`. Existing offsets are `0x00`
  (`reg_nco_freq`), `0x04` (`reg_dec_rate`), `0x08` RO
  (`reg_status`) — extend the existing read/write case statements
  (look for `s_axil_awaddr[3:2]` and `s_axil_araddr[3:2]`).
- Add a counter that increments on every accepted output beat
  (`m_axis_tvalid & m_axis_tready`). When the counter reaches
  `reg_samples_per_packet - 1`, drive `m_axis_tlast = 1` for that
  cycle and reset the counter. All other times `m_axis_tlast = 0`.
- Update the assigns at the bottom of the module:
  ```verilog
  assign m_axis_tdata  = {hb_Q_out, hb_I_out};
  assign m_axis_tvalid = hb_I_valid & hb_Q_valid;
  // add: assign m_axis_tlast = …;
  ```
- Add `output wire m_axis_tlast` to the port list if it isn't there.

Don't touch `duc_top.v` (TX path, not affected).

### 2. `firmware/src/platform/ddc_ctrl.{c,h}` (optional but tidy)

Add `void ddc_set_samples_per_packet(uint32_t n);` that writes to
`EBAZ_DDC_BASE + 0x0C`. Call it once from the boot task in
`firmware/src/main.c` with a value matching the rx_task's BTT —
look in `firmware/src/platform/axi_dma.c` for the buffer-size
constant. If the firmware default matches the RTL default (4096),
you can skip this for v1.

### 3. `CLAUDE.md`

Add `0x0C` to the DDC register-offsets table.

### 4. `docs/PROGRESS.md`

Mark row 3.8 ✅ when verified on hardware.

### 5. `docs/NEXT_STEPS.md`

Mark row 1 ✅.

## Build chain (from repo root)

```bash
# 1. FPGA — Vivado 2022.2
source /home/user/Xilinx/Vivado/2022.2/settings64.sh
cd hardware/scripts
rm -rf ../ebaz4205_sdr_vivado
vivado -mode batch -nojournal -nolog -source create_project.tcl
vivado -mode batch -nojournal -nolog -source run_bd.tcl
vivado -mode batch -nojournal -nolog -source run_synth_impl.tcl
vivado -mode batch -nojournal -nolog -source export_xsa.tcl
# Verify run_synth_impl reports impl_1 status "write_bitstream Complete!"

# 2. Firmware — only if you changed C code. Otherwise skip to step 3.
source /home/user/Xilinx/Vitis/2022.2/settings64.sh
cd ../../firmware/vitis_ws/sdr_app/Release
make all                # uses existing platform; relinks if .c changed
# (The .xsa changed — strictly the Vitis platform should be re-generated
#  too. In practice the address map didn't change *type*, only added a
#  register, and bare `make` keeps working. If you hit weird linker
#  errors, run `xsct ../../../scripts/vitis_build.tcl` to regenerate.)

# 3. BOOT.bin — repack with new bitstream
cd ../../../sd_boot
bootgen -arch zynq -image boot.bif -o BOOT.bin -w on
md5sum BOOT.bin
```

## Verify on hardware

Ask the user to copy `firmware/sd_boot/BOOT.bin` to the SD card,
power-cycle, and paste UART output.

**Pass criterion**: `[rx_task] DMA timeout` no longer appears.
The rx_task should now either succeed silently or print whatever
it logs on each successful DMA buffer (look in
`firmware/src/tasks/rx_task.c`).

If TLAST is misaligned and the DMA truncates rather than timing
out, you'll see corrupt-looking transfers but no timeout — that's
also progress; iterate on the counter logic.

## Gotchas

- The DDC AXI-Stream master reaches the DMA through an
  `axis_clock_converter` (60 MHz → 100 MHz). TLAST passes through
  verbatim — no special handling needed there.
- The DMA is configured with `c_s2mm_burst_size=16` and 32-bit
  TDATA. `samples_per_packet` should be a multiple of 16 to avoid
  odd-burst tail effects. 4096 is fine.
- LEDs are active-LOW on this board. The `mmcm_locked` heartbeat
  in `sdr_top.v` already handles that.
- If anything goes sideways, `nand_backup/fsbl_uboot.bin` is the
  original PetaLinux boot image — the user can re-flash it to
  recover the board to a known-good state.

## When done

```bash
git add hardware/rtl/ddc_top.v \
        firmware/src/platform/ddc_ctrl.c \
        firmware/src/platform/ddc_ctrl.h \
        firmware/src/main.c \
        CLAUDE.md \
        docs/PROGRESS.md \
        docs/NEXT_STEPS.md \
        firmware/sd_boot/BOOT.bin
git commit -m "ddc_top: assert m_axis_tlast every N samples to clear DMA timeout"
```

Short one-line commit message, no Co-Authored-By trailer (user
preference; see `MEMORY.md`). Then summarise for the user (~5
lines): what changed, what new UART output shows, any follow-ups
discovered.
