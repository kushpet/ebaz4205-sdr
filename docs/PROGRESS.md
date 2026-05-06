# Progress tracker

> **Pivot 2026-05-06:** RemoteInput (UDP+cm256+HTTP REST) abandoned;
> moving to SDRangel `RemoteTCPInput` over a single TCP socket — see
> [`sdra-tcp-plan.md`](sdra-tcp-plan.md). Rows 2.6–2.11, 3.1, 3.3, 3.9
> below describe deleted code; kept here only as bring-up history. The
> FPGA pipeline (Phase 1), platform/DMA/lwIP-init (2.1–2.5), and
> hardware bring-up (3.4–3.8) carry over unchanged.

Live status of the v2 plan. ✅ done, ⚠ partial / has caveat, ⬜ pending.

## Phase 1 — FPGA (Vivado 2022.2)

| # | Item | Status | Files |
|---|------|--------|-------|
| 1.1  | XDC pin/IOSTANDARD constraints   | ✅ | `hardware/constraints/ebaz4205.xdc` (extended with PHY refclk + LEDs) |
| 1.2  | Vivado project + build Tcl       | ✅ | `hardware/scripts/create_project.tcl`, `build.tcl` |
| 1.3  | MMCM 100→60/25 MHz               | ✅ | `hardware/rtl/clk_60mhz.v` |
| 1.4  | ADC interface (AD9226)           | ✅ | `hardware/rtl/adc_if.v`, `sim/tb_adc_if.v` |
| 1.5  | DAC interface (DAC904)           | ✅ | `hardware/rtl/dac_if.v`, `sim/tb_dac_if.v` |
| 1.6  | NCO + complex mixer              | ✅⚠ | `hardware/rtl/nco.v`, `complex_mixer.v` (DDC Q-sign mirror — see CLAUDE.md) |
| 1.7  | CIC dec/int                      | ✅ | `hardware/rtl/cic_decimator.v`, `cic_interpolator.v`, `sim/tb_cic.v` |
| 1.8  | HB FIR dec/int (Parks–McClellan) | ✅ | `hardware/rtl/hb_fir_decimator.v`, `hb_fir_interpolator.v` |
| 1.9  | DDC top                          | ✅ | `hardware/rtl/ddc_top.v` |
| 1.10 | DUC top                          | ✅ | `hardware/rtl/duc_top.v` |
| 1.11 | Block Design (PS7 + DMA + DDC/DUC + MMCM) | ✅ | `hardware/scripts/create_bd.tcl` (rewritten — MMCM is inside the BD; DDC/DUC clocked at 60 MHz, AXI fabric at 100 MHz) |
| 1.12 | Toplevel wrapper                 | ✅ | `hardware/rtl/sdr_top.v` (ODDR for `CLK_ADC`, LED heart-beat) |

## Phase 2 — Firmware (Vitis 2022.2, bare-metal + FreeRTOS)

| # | Item | Status | Files |
|---|------|--------|-------|
| 2.1  | Platform init + linker layout   | ✅ | `firmware/src/platform/platform_init.{c,h}`, `firmware/lscript.ld` |
| 2.2  | IP101G MDIO driver              | ✅ | `firmware/src/platform/ip101g.{c,h}` |
| 2.3  | AXI DMA wrapper + ISR           | ✅ | `firmware/src/platform/axi_dma.{c,h}` |
| 2.4  | lwIP + GEM0 init                | ✅ | `firmware/src/network/net_init.{c,h}` |
| 2.5  | DDC/DUC control                 | ✅ | `firmware/src/platform/ddc_ctrl.{c,h}` |
| 2.6  | SDRAngel Remote frame structs   | ✅ | `firmware/src/protocol/sdrangel_frame.{c,h}`, `docs/sdrangel_protocol.md` |
| 2.7  | cm256 FEC                       | ⚠ | `firmware/src/protocol/cm256.{c,h}` — pass-through stub for nb_fec_blocks=0; replace with upstream catid/cm256 to enable FEC |
| 2.8  | UDP TX + rx_task                | ✅ | `firmware/src/network/udp_tx.{c,h}`, `tasks/rx_task.{c,h}` |
| 2.9  | UDP RX + tx_task                | ✅ | `firmware/src/network/udp_rx.{c,h}`, `tasks/tx_task.{c,h}` |
| 2.10 | HTTP REST server                | ✅ | `firmware/src/network/http_rest.{c,h}` |
| 2.11 | IQ convert helpers              | ✅ | `firmware/src/protocol/iq_convert.{c,h}` |
| —    | `main.c`                         | ✅ | `firmware/src/main.c` |

## Phase 3 — Integration & debug

| # | Item | Status | Files |
|---|------|--------|-------|
| 3.1 | Python test scripts | ✅ | `tools/test_udp_rx.py`, `tools/test_udp_tx.py` |
| 3.2 | ILA additions       | ⬜ | (deferred — purely a Vivado IDE step) |
| 3.3 | Debug checklist     | ✅ | `docs/debug.md` |
| 3.4 | FPGA build (Vivado) | ✅ | bitstream + .xsa produced; 0 errors / 0 critical warnings; WNS +1.977 ns |
| 3.5 | Firmware build (Vitis) | ✅ | sdr_app.elf + sdr_fsbl.elf; lwIP socket API on FreeRTOS; heap=1 MB |
| 3.6 | SD-card BOOT.bin    | ✅ | `firmware/sd_boot/BOOT.bin` (FSBL + bitstream + sdr_app) |
| 3.7 | First boot on hardware | ✅ | UART1 banner, lwIP up, PHY autoneg complete, all tasks scheduled |
| 3.8 | DMA RX path working | ✅ | `ddc_top.v` asserts `m_axis_tlast` every `samples_per_packet` beats (reg 0x0C); BD sets DMA `c_sg_length_width=23` so 64 KiB transfers fit; firmware sets `samples_per_packet = EBAZ_DMA_BUF_BYTES/4` |
| 3.9 | End-to-end SDRAngel | ⬜ | Wire format never validated against real SDRAngel; only loopback Python tools |

## Open caveats

1. **DDC mirror.** `complex_mixer.v` produces `Q = data·sin` instead of
   `Q = −data·sin`. Spectrum is mirrored. Acceptable for v1; SDRAngel
   has a "swap I/Q" toggle. Fix later.
2. **cm256 stub.** `firmware/src/protocol/cm256.c` succeeds only when
   `recovery_count == 0`. Drop-in catid/cm256 source when FEC is needed.
3. **NCOs not phase-locked across DDC/DUC.** Each top-level instantiates
   its own `nco_direct`. They share the `freq_word` register but not the
   accumulator; relative phase is undefined. Fine for half-duplex SDR.
4. **lwIP NETCONN, not RAW.** Higher latency than RAW, but easier for a
   FreeRTOS-on-bare-metal build. Revisit if jitter is unacceptable.
5. **PHY refclk pin.** XDC routes `PHY_REFCLK_25MHZ` → U18. Verify on
   the schematic that U18 is wired to IP101G `XI` and not to a strap.
6. ~~**DDC `m_axis_tlast` is not driven.**~~ Resolved: `ddc_top.v` asserts
   TLAST every `reg_samples_per_packet` beats (AXI-Lite reg 0x0C, default
   4096); firmware writes `EBAZ_DMA_BUF_BYTES/4` at boot.
7. **EBAZ4205 board peculiarities** (worth their own Tcl):
   - DDR3 chip is `MT41K128M16 JT-125` (16-bit). Default Zynq-7010 PCW
     does NOT match — silently brings up a controller that slverr's on
     every access (wedges DAP). Use the board file under
     `hardware/Board files/ebaz4205/1.0/preset.xml`.
   - Console is **UART1** on MIO 24/25, not UART0.
   - GEM0 is on **EMIO** (PL pins, bank 34) — IP101G via MII.
   - IP101G is strapped to **MDIO address 0x00**, not 0x01.
   - LEDs are **active-low** (output 0 lights up).
8. **Xilinx lwIP-on-FreeRTOS port quirks** (already worked around in
   `firmware/src/network/net_init.c`, but document for the next agent):
   - Their `tcpip_init()` skips `lwip_init()` unless `LWIP_XINIT` is
     defined in `lwipopts.h`. Without that, `mem_mutex` is never
     initialised and the first `mem_malloc` traps in
     `queue.c:1507 configASSERT( pxQueue->uxItemSize == 0 )`.
   - Their `lwip_sock_init()` calls `tcpip_init()` and then busy-waits
     on a flag. Deadlocks when the calling task has higher priority
     than `TCPIP_THREAD_PRIO` (3 by default). We call `tcpip_init()`
     directly instead.
   - The port already creates its own `XScuGic`; do **not** call
     `XScuGic_CfgInitialize` again. Use `extern XScuGic xInterruptController`.
   - BSP default heap is 64 KB. Bump to 1 MB minimum (lwIP+tasks).
