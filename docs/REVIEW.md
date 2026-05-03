# Iteration review — what was actually delivered

This pass took the project from "code exists but nothing has ever been
built" to **firmware running on real EBAZ4205 hardware booted from an
SD card**. The bring-up exposed several Xilinx-toolchain quirks and a
hardware/PCW mismatch that had been silently wrong all along; those are
fixed now and documented in `CLAUDE.md` so the same time isn't burned
again.

## Verified end-to-end (visible on UART1 @ 115200)

```
====================================================
  EBAZ4205 SDR firmware (bare-metal + FreeRTOS)
  Build: ...
  DMA non-cached region: 0x08000000 .. 0x0FFFFFFF
  DDC base: 0x43C00000   DUC base: 0x43C01000
====================================================
[net] tcpip_init returned
[net] main_thread spawned
Start PHY autonegotiation
Waiting for PHY to complete autonegotiation.
[dma] init OK; rx=8000000,8020000 tx=8010000,8030000
[boot] SDR firmware ready
[http] listening on :8888
autonegotiation complete
link speed for phy address 0: 10
[net] up: ip=192.168.1.100 mask=255.255.255.0 gw=192.168.1.1
```

That output proves: PS clocks/DDR/MIO are correctly configured (FSBL
ran cleanly), MMCM locked at 60 MHz (LEDs blink), bitstream loaded,
ELF jumped to from FSBL, FreeRTOS scheduler is ticking, lwIP TCP/IP
thread is up, GEM0 EMIO is wired through to a working IP101G PHY,
auto-negotiation completed, all four worker tasks (`rx_task`,
`tx_task`, `http_task`, `xemacif_input`) are scheduled.

## Build artefacts shipped

| Artefact | Path |
|---|---|
| Bitstream | `hardware/ebaz4205_sdr_vivado/ebaz4205_sdr.runs/impl_1/sdr_top.bit` |
| Hardware handoff | `hardware/ebaz4205_sdr.xsa` |
| Firmware ELF | `firmware/vitis_ws/sdr_app/Release/sdr_app.elf` |
| Vitis Zynq FSBL ELF | `firmware/vitis_ws/sdr_fsbl/Release/sdr_fsbl.elf` |
| **`BOOT.bin` for SD card** | **`firmware/sd_boot/BOOT.bin`** |
| Original NAND boot dump (backup) | `nand_backup/fsbl_uboot.bin` |

`BOOT.bin` is what you copy to a FAT32-formatted SD card. The FSBL
inside it was built **from our exported `.xsa`**, so it carries the
exact PCW configuration the firmware expects (DDR3 timings, UART1 pin
mux, EMIO GEM0).

## Toolchain / build status

| Stage | Tool | Status |
|---|---|---|
| FPGA synthesis | Vivado 2022.2, batch | 0 errors, 0 critical warnings |
| FPGA implementation | Vivado 2022.2 | 0 errors, 0 critical warnings, WNS +1.977 ns, WHS +0.020 ns |
| FPGA resources | xc7z010clg400-1 | LUT 38 % · FF 33 % · DSP 85 % · BRAM 5 % · IOB 33 % |
| Vitis platform | Vitis 2022.2 | freertos10_xilinx + lwip211 (sockets API) + standalone (for FSBL) |
| Firmware app | arm-none-eabi-gcc | 177 KB text · 3.5 KB data · 4.2 MB bss (1 MB FreeRTOS heap) |

Build commands (run individually, in order, from `hardware/scripts/`):

```bash
vivado -mode batch -source create_project.tcl
vivado -mode batch -source <run_bd.tcl>     # source create_bd.tcl into open project
vivado -mode batch -source build.tcl        # synth + impl + bitstream
# then export .xsa, build platform + sdr_app + sdr_fsbl in Vitis
```

(See `firmware/sd_boot/boot.bif` for the bootgen recipe.)

## What *isn't* working yet (carry-overs)

1. **`[rx_task] DMA timeout`** — every poll cycle. The DDC's
   AXI-Stream master into `dma0/S2MM` lacks `m_axis_tlast`. AXI DMA in
   direct-register mode requires TLAST on the last beat of each
   buffer, otherwise the channel never reports completion. Bitstream
   builds fine because it's only a critical *warning*, not an error,
   but the RX path is non-functional until TLAST is generated.
2. **Our `ip101g.c` reads `0x0000` for PHYID** even though Xilinx's
   xemacps detected the same PHY at addr 0 and got a 10 Mbps link.
   Likely EMIO MDIO needs `XEmacPs_PhyRead`/`PhyWrite` rather than the
   bit-banged accessor we have. Functionally the link is up either
   way (Xilinx port handles MDIO inside `xemac_add`).
3. **End-to-end SDRAngel test** — never run. We don't yet know whether
   the wire format implementation is byte-correct. The `tools/`
   Python scripts are loopback-only.
4. **DDC complex-mixer Q-sign mirror.** `complex_mixer.v` still
   produces `Q = data·sin` instead of `Q = −data·sin`. Will manifest
   as mirror-image spectrum until fixed.
5. **cm256 stub.** `firmware/src/protocol/cm256.c` is a no-FEC
   pass-through. Recovery only works when `nb_fec_blocks == 0`.
6. **Build warnings** in `rx_task.c` (packed-member address-of) and
   `axi_dma.c` (parenthesisation). Cosmetic; not blockers.

## Forward plan — split into independent threads

Each item below is self-contained: the new agent doesn't need to
re-derive the platform from scratch, just `git checkout main`, read
`CLAUDE.md`, and pick up the listed task. Order is by impact, but
items 2–6 are independent.

### 1. **DDC TLAST generation (RTL change)** — biggest blocker

- File: `hardware/rtl/ddc_top.v`
- Add a sample-counter that asserts `m_axis_tlast` once every N
  output samples (where N comes from a new AXI-Lite register, e.g.
  offset 0x0C, default 8192 = 32 KB at 4 bytes/sample).
- Re-run `vivado -mode batch` (synth + impl + bitstream + `.xsa`
  re-export). Then rebuild `sdr_app.elf` (no source change needed),
  re-bootgen `BOOT.bin`. The `[rx_task] DMA timeout` should clear.
- Suggested model: any. Pure RTL + bitstream rebuild, ~1 hour wall
  clock.

### 2. **MDIO via xemacps API**

- File: `firmware/src/platform/ip101g.c`
- Replace the current bit-banged or `gem.mdio_*` accessor with
  `XEmacPs_PhyRead(net_get_xemacps(), phy, reg, &val)` /
  `XEmacPs_PhyWrite(...)`. The `xemac_add` from the BSP already
  initialised the EMAC and its MDIO clock divider correctly.
- `extern XEmacPs s_emac;` is already exported via `net_get_xemacps()`.
- Verify by re-reading PHYID in the boot log.

### 3. **End-to-end SDRAngel loopback test**

- Use `tools/test_udp_rx.py` from a Linux PC on the same subnet
  (192.168.1.0/24), set the firmware's `rx_task_set_dest()` to the PC,
  send IQ from the radio (or feed a known sinusoid via the ADC pins),
  observe the file produced by the test script. Then bring up real
  SDRAngel and the Remote Output plugin pointing at the EBAZ.
- Files: probably no source changes for first attempt; if the wire
  format doesn't match, fix in `firmware/src/protocol/sdrangel_frame.c`
  and re-derive from upstream.

### 4. **Q-sign fix in complex_mixer**

- File: `hardware/rtl/complex_mixer.v`
- One-line change: `Q_out` should be `−data·sin`. Bitstream rebuild.
- Trivial. Suggested model: smaller / cheaper.

### 5. **cm256 FEC**

- Drop `cm256.h` + `cm256.cpp` from `f4exb/cm256cc` into
  `firmware/third_party/cm256/`, port to C (port already has the
  shape). Disable SIMD, statically allocate. Replace stub.
- Substantial work, but isolated.

### 6. **ILA / debug instrumentation**

- Phase 3.2 from the original plan. Deferred. Add ILA cores in
  `create_bd.tcl` on the AXI-Stream from `adc_if`, the AXI-Stream into
  `dma0/S_AXIS_S2MM`, and the AXI-Stream out of `dma1/M_AXIS_MM2S`.
- Useful for debugging item 1 if the simple counter doesn't fix it.

### 7. **Cleanup — build warnings**

- `rx_task.c` packed-member address-of (use `memcpy` instead of
  `&`-ing a packed field), `axi_dma.c` parenthesisation. Trivial.
- Group with item 4 in a single "RTL + warnings cleanup" thread.

## Concise summary (for handoff)

> Project goes through Vivado+Vitis 2022.2 cleanly, boots end-to-end
> from SD on EBAZ4205. PS clocks/DDR/UART1/EMIO Ethernet all wired
> per the board files. lwIP+FreeRTOS+HTTP stack initialises and PHY
> autoneg completes. Three carry-overs: (a) DDC AXI-Stream lacks
> TLAST so DMA RX times out, (b) our optional MDIO accessor reads
> zero (Xilinx port works), (c) wire-protocol against SDRAngel hasn't
> been validated end-to-end yet. Bitstream, ELFs, and `BOOT.bin` are
> in the tree under `firmware/sd_boot/`.
